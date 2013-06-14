package LFIBot::Plugins::KOTH ;

=pod

=head1 NAME 

    LFIBot::Plugins::KOTH

=cut

use strict;
use warnings;
use base qw| LFIBot::Plugin |;
use Encode;
use LWP::UserAgent;
use HTTP::Response::Encoding;
use HTML::TreeBuilder::XPath;
use HTML::HeadParser;
use Data::Dumper; 
use Cache::FileCache; 

my $map = {
    'itellyouwhat'     => 'Hank-Hill',
    'thatboyaintright' => 'Bobby-Hill',
};

sub itellyouwhat {
    my ( $class, $bot, $struct ) = @_;

    $class->_send_quote( $bot, $struct, 'itellyouwhat' );

}

sub itellyawhut {
    my ( $class, $bot, $struct ) = @_;

    $class->_send_quote( $bot, $struct, 'itellyouwhat' );

}
 
sub thatboyaintright {
    my ( $class, $bot, $struct ) = @_;

    $class->_send_quote( $bot, $struct, 'thatboyaintright' );

}

sub damnitbobby {
    my ( $class, $bot, $struct ) = @_;

    $class->_send_quote( $bot, $struct, 'thatboyaintright' );

}
   
sub _send_quote {
    my ( $class, $bot, $struct, $type ) = @_;

    my $quotes_ref = eval { $class->_scrape_quotes( $type, $bot ) };

    return unless $quotes_ref;

    my $quote = $quotes_ref->[ rand @{$quotes_ref} ];

    $bot->message( $struct->{channel_raw}, $quote || 'no quote' )
}

sub _scrape_quotes {
    my ( $class, $type, $bot ) = @_;

    my $cache = new Cache::FileCache({ 
                    namespace          => 'KOTH',
                    default_expires_in => '1 day',
                    directory_unask    => 0077,
                });

    my $quotes_ref = $cache->get($type);

    return $quotes_ref if defined $quotes_ref;
   
    my $ua  = LWP::UserAgent->new;
    $ua->agent('itellyouwhat/0.001');  
    $ua->timeout(5);

    my $url = sprintf('http://www.hankhillquotes.com/quotes/%s/',
                      $map->{$type} );

    my $res = $ua->get($url);
    
    if ( $res->is_error )  {
        $bot->log( 'error', "Error: ". $res->status_line );
        return;
    }
    
    my $content = decode $res->encoding, $res->content; 

    my $koth_tree = HTML::TreeBuilder::XPath->new;  
    $koth_tree->parse_content($content);  

    my $path = q|//tr/td[@id="contenttd"]/div/ul/li|;

    my $results = [ map { $_->as_text } $koth_tree->findnodes($path)  ];

    $cache->set( $type, $results );

    $koth_tree->delete;
     
    return $results;
}

sub koth {
    my ( $class, $bot, $struct ) = @_; 

    $struct->{args} =~ s/^\s*//g;
    $struct->{args} =~ s/\s*$//g; 

    my @args = split( /\s+/, $struct->{args} ); 

    if ( $args[0] eq 'purge' ) {
        my $cache = new Cache::FileCache({ 
                        namespace          => 'KOTH',
                        default_expires_in => '1 day',
                        directory_unask    => 0077,
                    });

        $cache->purge() ; 

        $bot->tell_admins('Purged KOTH cache'); 
    }
}    

our @ADMIN_COMMANDS = qw| koth |;
our @COMMANDS       = qw| itellyouwhat itellyawhut damnitbobby
                          thatboyaintright |;
 
1;
