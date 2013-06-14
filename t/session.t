 #!/usr/bin/perl

use strict;
use warnings;
BEGIN {
    use local::lib;
    my ( $vol, $root_dir, $file) = File::Spec->splitpath(File::Spec->rel2abs($0));
    sub CONFIG_DIR { $root_dir };  
}
use LFIBot::Session;
use POE qw| Component::Server::IRC | ;
use Test::More; # tests => 4; 


my $auth_bot = POE::Component::IRC->spawn(
    plugin_debug => 1,
    flood        => 1,
    alias        => 'bot2',
);

my $admin = POE::Component::IRC->spawn(
    plugin_debug => 1,
    flood        => 1,
    alias        => 'bot2',
); 

my $ircd = POE::Component::Server::IRC->spawn(
    servername   => 'poco.server.irc',
    Auth         => 0,
    AntiFlood    => 0,
    plugin_debug => 1,
    flood        => 1,
    MOTD         => [qq|welcome to the test server|]
);  


POE::Session->create(
   package_states => [
       main => [qw(
           _start
           ircd_listener_add
           ircd_listener_failure
           ircd_daemon_nick
           ircd_daemon_join
           irc_msg
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
    $ircd->yield( set_motd => ['welcome to the test server'] );
    $auth_bot->yield(register => 'all');
    $auth_bot->yield(connect => {
        nick    => 'auth_bot',
        server  => '127.0.0.1',
        port    => 56667,
        ircname => 'auth_bot',
    });

    $admin->yield(register => 'all');
    $admin->yield(connect => {
        nick    => 'rfi',
        server  => '127.0.0.1',
        port    => 56667,
        ircname => 'rfi',
    });  
    
    $heap->{bot_session} = LFIBot::Session->spawn({ 
                              server_name => 'pocotest',  
                              config_file => sprintf('%s/lfi_test.yml', CONFIG_DIR )
                           });

    #$heap->{bot_sessi}->yield('irc_376');
}  

sub ircd_daemon_nick {
    my ($kernel, $heap, $user) = @_[KERNEL, HEAP, ARG0];

    pass("$user connected") if $user eq 'lfi';
    #$kernel->yield( 'irc_376' ); 

    diag("$user connect\n");

}

sub ircd_daemon_join {
    my ($kernel, $heap, $who, $where ) = @_[KERNEL, HEAP, ARG0, ARG1];     

    my ($user) = ( split('!', $who))[0];
        
    if ($user eq 'lfi' && $where eq '#test' ) {

        is( $heap->{bot_session}->{session}->get_heap()->{authed}, 1 , 'authed before join' );
        is( $heap->{bot_session}->{bot}->status(), 'lfi bot authed and online', 'status set' ); 
        pass('joined channel')
    }
    else {
        fail("$who $user joined $where")
    }

    $kernel->delay('_shutdown', 3); 
}

sub irc_msg {
    my ($kernel, $heap, $sender, $who, $where, $what) = @_[KERNEL, HEAP, SENDER, ARG0 .. ARG2];

    my $recip = $where->[0];

    if ( $recip eq 'auth_bot') {
        if ( $what eq 'auth string') {
            pass('bot authed');
            $auth_bot->yield( privmsg => 'lfi', 'auth successful' );
        }
        else {
            fail('incorrect auth string');
        }
    }
    elsif ( $recip eq 'rfi') {
        if ( $what eq 'lfi bot connected') {
            $heap->{rfi_msgs}++;
            pass('admin notified bot connected');
        }
        elsif ( $what eq 'lfi bot authed') {
            $heap->{rfi_msgs}++;
            pass('admin notified bot authed');
        } 
        elsif ( $what eq 'lfi bot joined #test') {
            $heap->{rfi_msgs}++;
            pass('admin notified bot join #test');
        } 
        else {
            fail("unknown message to rfi: $what");
        }
    }
    else {
        print "$recip\n";
    }
    
}

sub _shutdown {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    is( $heap->{rfi_msgs},  3, 'admin got all messages');

    diag('Shuting down');
    $kernel->alarm_remove_all();
    $ircd->yield('shutdown');
    $auth_bot->yield('shutdown');
    $admin->yield('shutdown'); 
    $heap->{bot_session}->stop();

} 

sub diagn {
    my ($message) = @_;

    print "$message\n";

}

done_testing();
