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
use Data::Dumper;

my $admin = POE::Component::IRC->spawn(
    plugin_debug => 1,
    flood        => 1,
    alias        => 'botadmin',
); 

my $normal_user = POE::Component::IRC->spawn(
    plugin_debug => 1,
    flood        => 1,
    alias        => 'bot1',
);  

my $auth_bot = POE::Component::IRC->spawn(
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
           irc_public
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

    $normal_user->yield(register => 'all');
    $normal_user->yield(connect => {
        nick    => 'rev',
        server  => '127.0.0.1',
        port    => 56667,
        ircname => 'rev',
    });  
    
    $heap->{bot_session} = LFIBot::Session->spawn({ 
                               server_name => 'pocotest',  
                               data_file   => sprintf('%s/test.db', CONFIG_DIR ), 
                               config_file => sprintf('%s/lfi_test.yml', CONFIG_DIR ),
                               do_auth        => 0,
                           });

}  

sub ircd_daemon_nick {
    my ($kernel, $heap, $user) = @_[KERNEL, HEAP, ARG0];
                           
    diag("$user connected");

    if ( $user eq 'lfi' ) {
        $normal_user->yield( join => '#test')    
    }

} 

sub ircd_daemon_join {
    my ($kernel, $heap, $who, $where ) = @_[KERNEL, HEAP, ARG0, ARG1];     

    diag("$who joined channel $where");

    if ( $where eq '#test') {
        if ( ++$heap->{joins} == 2 ) {
            $normal_user->yield( privmsg => '#test' => 'lfi?');
        }
    }
  
}   

sub _shutdown {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    diag('Shuting down');
    $kernel->alarm_remove_all();
    $normal_user->yield('shutdown');
    $auth_bot->yield('shutdown'); 
    $admin->yield('shutdown'); 
    $heap->{bot_session}->stop();
    $ircd->yield('shutdown');
    #unlink sprintf('%s/test.db', CONFIG_DIR );  
}    

sub irc_msg {
    my ($kernel, $heap, $sender, $who, $where, $what) = @_[KERNEL, HEAP, SENDER, ARG0 .. ARG2];

    my $recip = $where->[0];
    diag("private $who $recip $what ");
    #if ( $recip =~ /^rfi/) {
    #    if ( $what =~ /rev sent admin command:/) {
    #        pass("admin notified command sent");
    #    }    
    #    
    #} 
    #if ( $recip =~ /lfi/ ) {
    #    if ( $what =~ /no user named rev/) {
    #        pass("checkd unauthed user");

    #        $normal_user->yield( privmsg => '#test' => 'lfi: get status'); 
    #        #$kernel->delay('_shutdown', 5);   
    #    } 
    #}
    #if ($recip =~ /auth_bot/) {
    #    if ( $what =~ /is authed rev/ ) {
    #        pass("asked if user was authed");
    #        $auth_bot->yield( privmsg => 'lfi' => 'no user named rev');  
    #    }
    #    elsif ( $what =~ /is authed rfi/ ) {
    #        #pass("asked if user was authed");
    #        $auth_bot->yield( privmsg => 'lfi' => 'rfi is authenticated');  
    #    }  
    #}
}

sub irc_public {
    my ($kernel, $heap, $sender, $who, $where, $what) = @_[KERNEL, HEAP, SENDER, ARG0 .. ARG2];

    my $recip = $where->[0]; 
    diag("public $who $recip $what ");

    if ( $recip =~ /#test/ ) {
        if ( $who =~ /lfi/ ) {
            if ( $what =~ /rev, / ) {
                pass("lfi? trigger hit");
                $normal_user->yield( privmsg => '#test' => 'check out http://weightgrapher.com its cool'); 
                
                $kernel->delay('_shutdown', 5); 
            }
        }

    }

}    

done_testing();
