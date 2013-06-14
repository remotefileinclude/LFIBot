package LFIBot::Logger;

use strict;
use warnings;
use Carp;
use Log::Log4perl;
use IRC::Utils qw|:ALL|; 

my $levels = {
    debug => 4,
    info  => 3,
    warn  => 2,
    error => 1
};

sub new {
    my ( $class , $opts ) = @_;
 
    $opts ||= {};

    croak('first arg is not a hashref')
        if ( ref($opts) ne 'HASH');

    $opts->{level} = defined $opts->{level} 
                     ? $opts->{level} 
                     : 'info';

    return bless $opts, $class;

}

sub log {
    my ( $self, $level, $message ) = @_;

    return unless $self->can($level);

    return 
        unless ( $levels->{ $self->{level} } >= $levels->{$level} ); 

    $self->$level($message);

}

sub error {
    my ( $self, $message ) = @_; 

    printf("ERROR - %s\n", $message ); 

}  

sub warn {
    my ( $self, $message ) = @_; 

    printf("WARN - %s\n", $message ); 

}
  
sub info {
    my ( $self, $message ) = @_;

    printf("INFO - %s\n", $message );

}

sub debug {
    my ( $self, $message ) = @_; 

    printf("ERROR - %s\n", $message ); 

} 

1;
