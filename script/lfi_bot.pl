#!/usr/bin/perl

use strict;
use warnings;
BEGIN {
    use local::lib;
    umask 0077;
};
use LFIBot::Session;


my $session = LFIBot::Session->spawn({ 
    server_name  => 'whatnet',
    config_file => './etc/lfi.yml'
});

$session->start ;

