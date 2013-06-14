package LFIBot::Handlers;

use strict;
use warnings;
use IRC::Utils qw|:ALL|;
use POE;
use Data::Dumper;
use Encode qw| encode_utf8 |;

our @EVENTS = qw| irc_001 irc_003 irc_public bot_authed irc_msg 
                  irc_notice delayed_action irc_join irc_part 
                  irc_disconnected |;

sub irc_001 {
    my ($kernel, $heap) = @_[KERNEL, HEAP]; 

    $heap->{bot}->tell_admins( sprintf('lfi bot connected to %s', 
                                        $heap->{bot}->server_name ) );

    $heap->{bot}->status('lfi bot online'); 

}

sub irc_003 {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ]; 

    if ( $heap->{bot}->do_auth() ) { 
        $heap->{bot}->auth();
    }
    else {
        $heap->{bot}->auto_join_channels();  
    }

}  

sub bot_authed {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ]; 
    
    $heap->{bot}->tell_admins('lfi bot authed');
    $heap->{bot}->status('lfi bot authed'); 
    $heap->{bot}->auto_join_channels(); 
}  

sub irc_public {
    my ($kernel, $heap, $who, $where, $what) = @_[KERNEL, HEAP, ARG0 .. ARG2];

    my $server_name   = $heap->{bot}->server_name; 
    my $server_conf   = $heap->{bot}->server_config;
    my $auth_handlers = $server_conf->{auth_handlers}; 
    my $prefix        = $server_conf->{cmd_prefix};

    my $nick = parse_user($who);
    
    my $nick_decoded    = decode_irc($nick);
    my $channel_decoded = decode_irc($where->[0] || '');
    my $what_decoded    = decode_irc($what);

    if ( my ( $cmd, $args ) = $what_decoded =~ /^\Q$prefix\E\s*([^\s]+)\s*([^\s].+)?/ ) {
        return if $heap->{throttle}->{$nick_decoded}; 
        return if $heap->{bot}->is_blacklisted($nick_decoded); 
        return if $heap->{cached_cmd}->{$nick_decoded} ;
    
        $args ||= '';

        my $cmd_struct = { 
            cmd     => $cmd,
            args    => $args,
            who     => $nick_decoded,
            channel => $channel_decoded,
            who_raw => $nick,
            channel_raw => $where->[0]
        };                                   

        if ( $heap->{bot}->is_admin_cmd($cmd) ) {

            $heap->{cached_cmd}->{$nick_decoded} = $cmd_struct; 
            $heap->{bot}->check_user_auth($nick);

        }
        elsif ( $heap->{bot}->is_cmd($cmd) ) {
            $heap->{bot}->tell_admins(
                            "$nick_decoded sent command: $cmd $args", 
                             $nick_decoded );  

            if ( my $delay = $heap->{bot}->throttle ) {

                my $throttle_clear = sub {
                   delete $heap->{throttle}->{$nick_decoded};
                };
                
                $heap->{throttle}->{$nick_decoded} = 1 ;

                $kernel->delay('delayed_action' => $delay, $throttle_clear );
            }  

            $heap->{bot}->run_command( $cmd_struct )     
        }
    }

    if ( my $trigger = $heap->{bot}->is_trigger($what_decoded) ) {

         my $trigger_struct = { 
            message => $what_decoded,
            who     => $nick_decoded,
            channel => $channel_decoded,
            who_raw => $nick,
            channel_raw => $where->[0],
            bot         => $heap->{bot}
        }; 

        $trigger->{process}->( $trigger_struct );
    }  

}

sub irc_notice {
    my ($kernel, $heap, $who, $where, $what) = @_[KERNEL, HEAP, ARG0 .. ARG2];

    my $nick = parse_user($who);

    my $nick_decoded    = decode_irc($nick);
    my $channel_decoded = decode_irc($where->[0] || '');
    my $what_decoded    = decode_irc($what); 

    return if $heap->{bot}->is_blacklisted($nick_decoded); 

    my $server_name   = $heap->{bot}->server_name;
    my $server_conf   = $heap->{bot}->server_config;
    my $auth_handlers = $server_conf->{auth_handlers};
    my $auth_service  = $auth_handlers->{auth_service};
    my $auth_success  = qr|\Q$auth_handlers->{auth_success}\E|;
    my $auth_failure  = qr|\Q$auth_handlers->{auth_failure}\E|; 
    my $user_authed   = qr|$auth_handlers->{user_authed}|;
    my $not_authed    = qr|$auth_handlers->{user_not_authed}|; 

    # TODO make a standard stripping function. On at least
    # one server I was getting unprintable characters coming
    # through and breaking nick comparisons
    $what_decoded  =~ s/[^[:print:]]+//g;

    return unless $what_decoded;
   
    if ( $nick_decoded eq $auth_service ) { 
        # Did the bot auth
        if ( $what_decoded =~ $auth_success ) {
            $heap->{authed} = 1;
            $kernel->yield('bot_authed');
        }
        elsif ( $what_decoded =~ $auth_failure ) {
            $heap->{bot}->tell_admins('lfi bot failed to auth'); 
            $heap->{bot}->disconnect(); 
            $heap->{bot}->shutdown(); 
        } 
        # is the user trying to run an admin command authed response
        # TODO This will break if the server returns the user name second,
        # In that case I'll have to make this work only with > 5.10 so
        # I can used named backreferences instead. 
        elsif ( my ( $user, $account ) = $what_decoded =~ $user_authed ) {
            
            if ( $heap->{bot}->is_admin($account) ) {
                
                $heap->{bot}->tell_admins(
                    sprintf('%s %s sent admin command %s %s', 
                             $user,
                             $account,
                             $heap->{cached_cmd}->{$user}->{cmd},  
                             $heap->{cached_cmd}->{$user}->{args} ),   
                    $account    
                );  
                
                $heap->{bot}->run_admin_cmd( $heap->{cached_cmd}->{$user} ) ;

            }
            else {
                $heap->{bot}->tell_admins("$user tried using admin commands");   
            }

            delete $heap->{cached_cmd}->{$user};     
        }
        elsif ( my ($f_user) = $what_decoded =~ $not_authed ) {
            $heap->{bot}->tell_admins("$f_user tried using admin commands");  
            delete $heap->{cached_cmd}->{$f_user};    
        }  
       
       return;
    }  

    if ( my ( $cmd, undef, $args ) = $what_decoded =~ /^([^\s]+)(\s+)?([^\s].+)?/ ) {

         return if $heap->{throttle}->{$nick_decoded};
         
         $args ||= '';

         my $cmd_struct = { 
             cmd     => $cmd,
             args    => $args,
             who     => $nick_decoded,
             who_raw => $nick
         };                                   

         if ( $heap->{bot}->is_admin_cmd($cmd) ) {
             return if $heap->{cached_cmd}->{$nick_decoded} ;
             
             $heap->{cached_cmd}->{$nick_decoded} = $cmd_struct; 
             $heap->{bot}->check_user_auth($nick);
         }
         elsif ( $heap->{bot}->is_cmd($cmd) ) {
             $heap->{bot}->tell_admins("$nick_decoded sent command $what_decoded", 
                                        $nick_decoded );  

             if ( my $delay = $heap->{bot}->throttle ) {

                my $throttle_clear = sub {
                   delete $heap->{throttle}->{$nick};
                };
                
                $heap->{throttle}->{$nick} = 1 ;

                $kernel->delay('delayed_action' => $delay, $throttle_clear );
             }

             $heap->{bot}->run_command( $cmd_struct )     
         }

         return;
    }   

    $heap->{bot}->tell_admins("Message from $nick_decoded : $what_decoded", 
                              $nick_decoded );
}

sub irc_msg {
    return irc_notice(@_);
}   

sub delayed_action {
    my ($code) = $_[ARG0];

    $code->();

}

sub irc_join {
    my ( $kernel, $heap, $who, $where ) = @_[KERNEL, HEAP, ARG0, ARG1]; 

    my $nick = parse_user($who);
    
    if ( $nick eq $heap->{bot}->server_nick ) {
        $heap->{bot}->tell_admins("$nick bot joined $where");   
    }
}

sub irc_part {
    my ( $kernel, $heap, $who, $where ) = @_[KERNEL, HEAP, ARG0, ARG1]; 

    my $nick = parse_user($who);
    
    if ( $nick eq $heap->{bot}->server_nick ) {
        $heap->{bot}->tell_admins("$nick bot left $where");   
    }
} 

sub irc_invite {


}

sub irc_disconnected {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP ];  

    $heap->{bot}->tell_admins( sprintf('lfi bot disconnected from %s', 
                                        $heap->{bot}->server_name ) ); 

    $heap->{bot}->status('disconnected');
}

1;
