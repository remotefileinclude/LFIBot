package LFIBot::Session;

use strict;
use warnings;
use Data::Dumper;
use LFIBot;
use POE;

sub spawn {
    my ( $class, $self ) = @_;

    die('first arg must be hash')
        unless ( $self && ( ref($self) eq 'HASH') ); 

    # This is a problem if we ever have more than 1 level of 
    # keys in our ocnfig
    my $config = { %{$self} }; 

    bless $self, $class;

    $self->{bot} = LFIBot->new($config); 

    $self->{session} = POE::Session->create(
        package_states => [
            $self->{bot}->handler_class  => $self->{bot}->handlers, 
            $self                        => [ qw| _start _shutdown | ]
        ],
        heap    => { bot => $self->{bot} },
        options => { 
            trace => $self->{poe_trace}, 
            debug => $self->{poe_debug} 
        },
    ); 
    
    $SIG{'INT'}  = $SIG{'TERM'} = sub { $self->stop }; 

    return $self;

}

sub start {
    POE::Kernel->run(); 
}
         
sub stop {
    my ($self) = @_;

    $self->{bot}->disconnect(); 
    $self->{bot}->shutdown();

}

sub _start {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];

    my $bot = $heap->{bot} ;
    $bot->connect();

}

sub _shutdown {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
    #print "Shutingdown session\n";
    my $bot = $heap->{bot} ;
    $bot->disconnect ;
    $bot->shutdown() ;
    
}  


1;
