#!/usr/bin/perl

use strict;
use warnings;
BEGIN {
    use local::lib;
    my ( $vol, $root_dir, $file) = File::Spec->splitpath(File::Spec->rel2abs($0));
    sub CONFIG_DIR { $root_dir }; 
} 
use LFIBot;
use POE qw|Component::Server::IRC|;
use Test::More tests => 2;


my $ircd = POE::Component::Server::IRC->spawn(
    Auth         => 0,
    AntiFlood    => 0,
    plugin_debug => 1,
    flood        => 1,
);

#my $lfi_bot = LFIBot->new({ server      => '127.0.0.1', 
#                            port        => 56667,
#                            config_file => sprintf('%s/lfi_test.yml', CONFIG_DIR )
#              });

my $lfi_bot = LFIBot->new({ 
                server_name => 'pocotest',
                config_file => sprintf('%s/lfi_test.yml', CONFIG_DIR ) 
              });
 
POE::Session->create(
   package_states => [
       main => [qw(
           _start
           ircd_listener_add
           ircd_listener_failure
           irc_001
           irc_error
           irc_disconnected
           _shutdown
       )],
   ],
   heap => { ircd => $ircd, bot => $lfi_bot },
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
    
    my $bot = $heap->{bot};

    diag('bot connecting');
    $bot->connect();
             
}

sub irc_error {
    diag('irc error:'.  $_[ARG0] );
}

sub irc_connected {
    my ($kernel) = $_[KERNEL];

    my $irc = $_[SENDER]->get_heap();
    diag( $irc->session_alias() . " connected");
} 

sub irc_disconnected {
    my ($kernel) = $_[KERNEL];

    pass('Disconnected');

    $kernel->yield('_shutdown'); 
}

sub irc_001 {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $bot = $heap->{bot}; 
    my $irc = $_[SENDER]->get_heap();

    pass( $irc->session_alias() . " logged in");

    $bot->disconnect();
    
}

sub _shutdown {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $bot = $heap->{bot};
    diag('Shuting down');
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');

    $bot->{poco_bot}->yield('shutdown');
}

