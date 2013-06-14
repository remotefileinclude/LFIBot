 #!/usr/bin/perl

use strict;
use warnings;
use LFIBot::Session;
use POE qw| Component::Server::IRC | ;
#use Test::More tests => 2; 


my $ircd = POE::Component::Server::IRC->spawn(
    Auth         => 0,
    AntiFlood    => 0,
    plugin_debug => 1,
    flood        => 1,
);  


POE::Session->create(
   package_states => [
       main => [qw(
           _start
           ircd_listener_add
           ircd_listener_failure
           _shutdown
       )],
   ],
   heap => { ircd => $ircd },
   #options => { trace => 1, debug => 1 },
); 

$poe_kernel->run(); 

sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
  
    $ircd->yield('register', 'all');
    $ircd->yield('add_listener', port => 56667);
    $kernel->delay(_shutdown => 60, 'Timed out'); 

}

sub ircd_listener_failure {
    my ($kernel, $op, $reason) = @_[KERNEL, ARG1, ARG3];
    $kernel->yield('_shutdown', "$op: $reason");
}

sub ircd_listener_add {
    my ($kernel, $heap, $port) = @_[KERNEL, HEAP, ARG0];
    diag("Server up on port $port");
    $kernel->yield('_shutdown');
}  

sub _shutdown {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    diag('Shuting down');
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');

} 

sub diag {
    my ($message) = @_;

    print "$message\n";

}
