#!/usr/bin/perl

use strict;
use warnings;
BEGIN {
    use local::lib;
    use LFIBot;
    use File::Spec;
    use Cwd qw| abs_path |;
    my ( $vol, $root_dir, $file) = File::Spec->splitpath(File::Spec->rel2abs($0));
    sub CONFIG_DIR { $root_dir };
    no strict 'refs';
    no warnings 'redefine';
    *{'LFIBot::server_name'} = sub { 'poco.server.irc' }
};

use Test::More;
use Data::Dumper;
use POE;

diag(CONFIG_DIR);

my @needed_params = qw| server port config_file |;

foreach my $needed_param ( @needed_params ) {
    my $param = shift @needed_params;

    eval {
        my $bot = LFIBot->new( { map { $_ => 'something' } @needed_params });
    };
    
    ok( $@ && $@ =~ /^Missing arg/, "Constructor failed without $param, $@");

    push(@needed_params, $param);
   
}

my $bot;
eval {
    $bot = LFIBot->new({ server     => 'test', 
                        port        => 324343, 
                        config_file => sprintf('%s/lfi_test.yml', CONFIG_DIR )
          });
};

ok(!$@, 'Constructor loaded with necessary params');

eval {
    $bot->validate_config();
};

ok(!$@, 'config file validated');

$bot->shutdown() ;

$poe_kernel->run();


done_testing();
