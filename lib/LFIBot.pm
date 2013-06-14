package LFIBot;

=pod

=head1 NAME

    LFIBot

=head1 SYNOPSIS

    my $session = LFIBot::Session->spawn({ 
        server_name  => 'whatnet',
        config_file => './etc/lfi.yml'
    });

    $session->start ; 

=head1 DESCRIPTION

   Another silly extensible irc bot. 

=cut

use warnings FATAL => qw| all |;;
use strict;
use POE qw| Component::IRC |;
use YAML qw| LoadFile |;
use Encode;
use LFIBot::Handlers;
use LFIBot::Startup;
use LFIBot::Triggers;
use LFIBot::AdminCommands;
use LFIBot::Commands;
use LFIBot::Logger;
use DBI;
use Carp;
use Data::Dumper;
use English qw| -no_match_vars |;


sub new {
    my ( $class, $self ) = @_;
    
    croak('first arg must be hash')
        unless ( $self && ( ref($self) eq 'HASH') );
    
    bless $self, $class;

    $self->{pid}      = $PID;
    $self->{encoding} ||= 'UTF-8';

    $self->{config} = LoadFile( $self->{config_file} ) 
        or croak("Error getting config: $!");

    $self->validate_config;

    my $server_config = $self->server_config;

    my $bot = POE::Component::IRC->spawn(
        Nick         => $server_config->{nick},
        Username     => $server_config->{nick},
        ircname      => $server_config->{ircname},
        plugin_debug => 1,
        alias        => 'LFI_BOT',
        server       => $server_config->{host},
        port         => $server_config->{port}, 
        Flood        => 1
    );  

    $self->{poco_bot} = $bot;
    $self->{logger}   = LFIBot::Logger->new(); 

    $self->load_modules();

    $self->startup_hooks();

    return $self;
}

sub load_modules {
    my ($self) = @_; 

    my $modules = $self->server_config->{modules} ;

    foreach my $module ( 'Core', @{$modules} ) {
        $self->log( 'info', "Loading module $module" );

        my $full_name = "LFIBot::Plugins::$module"; 

        local $@;
        eval "require $full_name";

        croak "Failed to load module $full_name : $@" if $@;

        {
            no strict 'refs';

            push @LFIBot::Startup::HOOKS, @{ $full_name .'::STARTUP' };
            push @LFIBot::Triggers::LIST, @{ $full_name .'::TRIGGERS' };

            foreach my $command ( @{ $full_name .'::COMMANDS' } ) {
                croak "Module command $command in conflict"
                    if LFIBot::Commands->can($command);

                croak "Module doesn't define admin command $command"
                    unless defined *{ $full_name .'::'. $command }{CODE} ;
                
                *{ 'LFIBot::Commands::'. $command } = 
                    sub {
                        shift @_;
                        $full_name->$command(@_);
                    };
            }

            foreach my $admin_command ( @{ $full_name .'::ADMIN_COMMANDS' } ) {
                
                croak "Module admin command $admin_command in conflict"
                    if LFIBot::AdminCommands->can($admin_command); 

                croak "Module doesn't define admin command $admin_command"
                    unless defined *{$full_name .'::'. $admin_command}{CODE};

                *{ 'LFIBot::AdminCommands::'. $admin_command } = 
                    sub {
                        shift @_;
                        $full_name->$admin_command(@_);
                    }; 
            }  
        }
    }

}

sub startup_hooks {
    my ($self) = @_;

    foreach my $startup_hook ( 
        reverse sort { $a->{priority} <=> $b->{priority} } @LFIBot::Startup::HOOKS   
    ) {
        $startup_hook->{hook}->($self);
    }    
}

sub handlers {
    my ($self) = @_;

    no strict 'refs';
    return \@{ $self->handler_class .'::EVENTS' };
}

sub handler_class {
    return 'LFIBot::Handlers';
}

sub db_connect {
    my ($self) = @_;

    return $self->{dbh} if $self->{dbh} ; 

    my $config = $self->server_config;

    $self->{dbh} = 
        DBI->connect( sprintf('dbi:SQLite:dbname=%s', $config->{data_file} ),'','' )
            or croak 'db connection error';

}

sub db_disconnect {
    my ($self) = @_;

    return unless $self->{dbh} ;

    $self->{dbh}->disconnect 
        or $self->log('warn', 'DBI error: '.  $self->{dbh}->errstr );

    delete $self->{dbh};

    return

}

sub db_reset {
    my ($self) = @_; 

    if ( !$self->{dbh} ) { 
        $self->db_connect();
        return;
    }

    # We forked and need to do some extra fun stuff 
    if ( $self->{pid} != $$ ) {

        my $child_dbh = $self->{dbh}->clone;

        $self->{dbh}->{InactiveDestroy} = 1;
        # Now DESTROY on the DBI object wont call
        # disconnect and mess with the parents connection
        delete $self->{dbh}; 

        $self->{dbh} = $child_dbh;

    }
    else {
        $self->db_disconnect();
        $self->db_connect();
    }

}

sub connect {
    my ($self) = @_;

    $self->{poco_bot}->yield( register => 'all' );
    $self->{poco_bot}->yield( connect => { Flood => 1 } ); 

}

sub server_nick {
    my ($self) = @_;

    return $self->{poco_bot}->nick_name;  
}

sub server_name {
    my ($self) = @_;

    return $self->{server_name};
}

sub server_config {
    my ($self) = @_;

    return $self->{config}->{servers}->{$self->server_name}; 
}

sub validate_config {
    my ($self) = @_;

    my $server_config = $self->server_config 
        or croak( 'No config defined for '. $self->server_name );

    my $config_template = {
        host      => '',
        port      => 0,
        admins    => [],
        channels  => [], 
        blacklist => [],
        do_auth   => 0,
        nick      => '',
        ircname   => '',
        user      => '',
        password  => '',
        cmd_prefix => '.lfi',
        throttle   => 5,
        data_file  => '/tmp/lfibot.db',
        modules    => [],
        quit_message  => '', 
        auth_handlers => {
            auth_service    => '',
            auth_string_t   => '',
            auth_success    => '',
            ask_if_authed   => '',
            user_authed     => '',
            user_not_authed => ''
        }

    };

    # If you're using recursion you're probably doing 
    # it wrong
    my $validator = sub {
        my ( $next, $self_config, $config, $template ) = @_;

        foreach my $setting ( keys %{$template} ) {
            $config->{$setting} = 
                delete $self_config->{$setting} if defined $self_config->{$setting};

            croak("$setting not definied")
                unless defined $config->{$setting};
        
            if ( ref($template->{$setting}) eq 'HASH' ) {
                croak("$setting is no a harshref") 
                    if ( ref($config->{$setting}) ne 'HASH');
                    
                $next->($next, $self_config->{$setting}, $config->{$setting}, $template->{$setting});
            }
            elsif ( my $type = ref($config->{$setting}) ) {
                croak("$setting is not ", ref($template->{$setting}) ) 
                    if ( $type ne ref($template->{$setting}))    
            }
        }

    };

    $validator->( $validator, $self, $server_config, $config_template );

}

sub auth {
    my ($self) = @_;
    
    my $server_conf   = $self->server_config;
    my $auth_handlers = $server_conf->{auth_handlers}; 
    my $auth_service  = $auth_handlers->{auth_service};
    my $auth_string_t = $auth_handlers->{auth_string_t}; 
    my $user          = $server_conf->{user};  
    my $password      = $server_conf->{password};   

    $auth_string_t =~ s/##user##/$user/;
    $auth_string_t =~ s/##password##/$password/;

    $self->message( $auth_service, $auth_string_t );

}

sub auto_join_channels {
    my ($self) = @_; 
    
    $self->join_channels( @{$self->server_config->{channels}} ); 

}

sub join_channels {
    my ($self, @channels) = @_;

    foreach my $channel ( @channels ) {
        $self->{poco_bot}->yield( join => $channel );
    } 
}

sub part_channels {
    my ($self, @channels) = @_;

    foreach my $channel ( @channels ) {
        $self->{poco_bot}->yield( part => $channel );
    } 
}  

sub throttle {
    my ($self) = @_;
    
    return $self->server_config->{throttle} ;
}

sub tell_admins {
    my ($self, $msg, $filter_admin) = @_;

    my $server_name   = $self->server_name; 

    $self->log('info', $msg );

    foreach my $user ( @{$self->server_config->{admins}} ) {
        next if ( $filter_admin && ( $user eq $filter_admin  ) );
        $self->message( $user, $msg );
    } 
}

sub is_admin_cmd {
    my ( $self, $cmd ) = @_;
    
    return if $cmd =~ /^_/; 

    return LFIBot::AdminCommands->can($cmd);

}

sub is_blacklisted {
    my ( $self, $user ) = @_;

    return unless ($user);
    
    if ( ! defined $self->{blacklist_hash} ) {
        my $server_name   = $self->server_name;  
        $self->{blacklist_hash} = {
             map { $_ => 1 } @{$self->server_config->{blacklist}}  
        }
    }

    return defined $self->{blacklist_hash}->{$user} ; 
}

sub is_admin {
    my ( $self, $user ) = @_;

    return unless ($user);
    
    if ( ! defined $self->{admins_hash} ) {
        my $server_name   = $self->server_name;  
        $self->{admins_hash} = {
             map { $_ => 1 }  @{$self->server_config->{admins}}  
        }
    }

    return defined $self->{admins_hash}->{$user} ;
}

sub check_user_auth {
    my ( $self, $who ) = @_;

    my $auth_handles  = $self->server_config->{auth_handlers};

    # $who could be a raw byte string
    # so we have to preencode the message to 
    # properly substitute in
    my $msg = $auth_handles->{ask_if_authed} ;
    $msg =  encode( $self->{encoding},  $msg );
    $msg =~ s/##user_authed##/$who/;
    
    $self->message( $auth_handles->{auth_service}, $msg , { raw => 1 });

}

sub is_cmd {
    my ( $self, $cmd ) = @_;

    return if $cmd =~ /^_/;

    return LFIBot::Commands->can($cmd); 
} 

sub is_trigger {
    my ( $self, $message ) = @_;

    foreach my $trigger ( @LFIBot::Triggers::LIST ) {
        if ( $message =~ $trigger->{pattern} ) {
            return $trigger;
        }
    }

    return;
}

sub run_command {
    my ( $self, $cmd_struct ) = @_;

    my $cmd = $cmd_struct->{cmd}; 

    # Probably duplicate validation here
    if ( $self->is_cmd($cmd) ) {
        LFIBot::Commands->$cmd( $self, $cmd_struct);
    }

}

sub run_admin_cmd {
    my ( $self, $cmd_struct ) = @_;

    my $cmd = $cmd_struct->{cmd}; 
    
    # Probably duplicate validation here
    if ( $self->is_admin_cmd($cmd) ) {
        LFIBot::AdminCommands->$cmd( $self, $cmd_struct);
    } 

} 

sub message {
    my ( $self, $where, $msg, $opts ) = @_;
    
    $msg = $self->encoder( $msg ) unless $opts->{raw};

    $self->{poco_bot}->yield( privmsg => $where => $msg  );  
}

sub notice {
    my ( $self, $where, $msg, $opts ) = @_;

    $msg = $self->encoder( $msg ) unless $opts->{raw}; 
    
    $self->{poco_bot}->yield( notice => $where => $msg  );  
} 


sub log {
    my ( $self, $level, $message ) = @_;

    $self->{logger}->log( $level, $message );

}

sub encoder {
    my ( $self, $msg ) = @_;

   return encode( $self->{encoding},  $msg ); 
}

sub disconnect {
    my ( $self, $q_message ) = @_;

    $q_message ||= $self->server_config->{quit_message} || 'bye';

    $self->{poco_bot}->yield( 'quit', $q_message );  

}

sub status {
    my ( $self, $status ) = @_;

    if ($status) {

        my $up_sth = $self->{dbh}->prepare(
            "UPDATE 
                lfibot
            SET 
                value=? 
            WHERE 
                key='status'");
        $up_sth->execute($status);
    }
    
    my $stat_sth = $self->{dbh}->prepare(
            "SELECT 
                value
            FROM 
                lfibot
            WHERE 
                key='status'");

    $stat_sth->execute() or return 'Unknown :\'('; 

    my $ret = $stat_sth->fetchrow_hashref() ;

    return ( $ret ) ? $ret->{value} : 'Unknown :\'(';

}

sub shutdown {
    my ($self) = @_;

    $self->{poco_bot}->yield('shutdown');   
}

sub do_auth {
    my ( $self, $set ) = @_;

    return $self->server_config->{do_auth};

}

1;
