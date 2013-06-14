package LFIBot::Plugins::Core;

=pod

=head1 NAME

    LFIBot::Plugins::Core

=head1 DESCRIPTION

   Implement core admin level commands

=cut

use strict;
use warnings;
use base qw| LFIBot::Plugin |; 
use Time::HiRes qw| usleep |;


## Admin commands

sub join {
    my ( $self, $bot, $struct ) = @_; 

    my @channels = split(/\s*,\s*/, $struct->{args});

    $bot->join_channels(@channels);

}

sub part {
    my ($self, $bot, $struct) = @_; 

    my @channels = split(/\s*,\s*/, $struct->{args} );

    $bot->part_channels(@channels);

}  

sub message {
    my ($self, $bot, $struct) = @_;  

    my ($who, $message) = split(/\s+/, $struct->{args}, 2 ); 

    $bot->message( $who, $message );
}

sub quit {
    my ($self, $bot, $struct) = @_;   
    
    $bot->disconnect( $struct->{args} );
    $bot->shutdown;
}  

## Commands 

sub get {
    my ( $self, $bot, $struct ) = @_;

    my @parsed_args = split(/\s+/, $struct->{args} );

    my $sub_func = shift @parsed_args; 
    $struct->{parsed_args} = \@parsed_args;

    my $get_method = 'get_' . $sub_func ;

    if ( __PACKAGE__->can($get_method) ) {
        __PACKAGE__->$get_method( $bot, $struct );
    }

}

sub help {
    my ( $self, $bot, $struct ) = @_;  

    my $manual=<<'END';
lfi bot commands:
   
   get (args) : get information about/from bot
     
     args: 
       - manual : this manual

   links ( user|channel|id:## ) ( like {string} or ... )? ( limit ## )?
( verbose )?  

     parameters:
     
       like      : one or more 'or' delimited strings to match against

       link
       
       limit (5) : limit the number of results
       
       verbose   : return more information about each link

       stats     : give some stat data instead of links

   ud <WORD> [ - <RESULT_NUM> [ examples ]  ] 

END

    foreach my $manual_line ( split(/\n/, $manual ) ) {
        usleep 20000;
        $bot->message( $struct->{who_raw}, $manual_line )  
    }

}

sub get_status {
    my ($self, $bot, $struct) = @_; 

    my $status = $bot->status();

    if ($struct->{channel}) {
        $bot->message( $struct->{channel_raw}, "Status: ".  $status )
    }
    else {
        $bot->message( $struct->{who_raw}, "status:". $status) 
    }

}   


## Triggers 


my $question  =  {  
    name    => 'what',
    pattern => qr/^lfi\s*\?/,
    process => sub {
        my ( $struct ) = @_; 
        
        my $nick =  $struct->{who} ; #split('!',$who);
        $struct->{bot}->message( $struct->{channel_raw}, 
                                 "$nick, I am here to serve and protect")
    }
 
};  


my $db_bootstrap = {  
    hook => sub {
        my ($bot) = @_;
        
        $bot->db_connect();

        $bot->{dbh}->do("CREATE TABLE IF NOT EXISTS `lfibot`( 
            `id`  INTEGER AUTO_INCREMENT,
            `key` VARCHAR(40) NOT NULL UNIQUE,
            `value` TEXT
        )" );

        my $sth = $bot->{dbh}->prepare(
            "INSERT OR IGNORE INTO 
                lfibot (key,value)
            VALUES('status', ?)");
     
        $sth->execute('starting');  

    },
    name     => 'setup bot status',
    priority => 99
};

our @TRIGGERS = ( $question );
our @ADMIN_COMMANDS = qw| join part message quit |;
our @COMMANDS       = qw| get help |;
our @STARTUP        = ( $db_bootstrap );


1;
