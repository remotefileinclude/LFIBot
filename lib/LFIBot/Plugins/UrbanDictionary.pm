package LFIBot::Plugins::UrbanDictionary ;

=pod

=head1 NAME 

    LFIBot::Plugins::UrbanDictionary

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
use Try::Tiny;


my $index = {
    first   => 0,
    second  => 1,
    third   => 2,
    fourth  => 3,
    fifth   => 4,
    sixth   => 5,
    seventh => 6,
    eighth  => 7
};

=head1 Commands

=over 4

=item  ud 

    ud <WORD> [ - [<RESULT_NUM>] [emaples]  ]

=back

=cut



sub ud {
    my ( $class, $bot, $struct ) = @_;

    return unless $struct->{channel};

    my ( $term, $opts ) = split('-', $struct->{args});

    my @opts = split(/\s+/, $opts || '');

    my $result_num ; 

    my $args = {
        examples => 0
    };

    foreach my $opt ( @opts ) {
        if ( defined $index->{ lc($opt) } ) {
            $result_num = $opt;
            next;
        }

        $args->{lc($opt)} = 1
            if defined $args->{lc($opt)};
    }    

    my $result = eval { $class->_scrape_ud( $term, $bot ) };
     
    return unless $result;

    my $index_num = $result_num ? $index->{ lc($result_num) } : 0 ; 

    if ( int @{$result->{word}} == 0  ) {
         $bot->message( $struct->{channel_raw}, 'No results found' ); 
    }
    else {
        my $definition = sprintf('%s : %s', $term, $result->{definition}->[$index_num] );
        my $examples   = sprintf('examples: %s', $result->{examples}->[$index_num] ); 

        $bot->message( $struct->{channel_raw}, $definition );
        $bot->message( $struct->{channel_raw}, $examples ) if $args->{examples};  

        if ( ( int @{$result->{word}} > 1 ) && !$index_num ) {
            $bot->message( $struct->{channel_raw}, 
                           sprintf('%i more results', int @{$result->{word}} -1 , $term  )  
                  )  
        }
    }
   
}

sub _scrape_ud {
    my ( $class, $term, $bot ) = @_;

    my $cache = new Cache::FileCache({ 
                    namespace          => 'UrbanDictionary',
                    default_expires_in => '1 day',
                    directory_unask    => 0077,
                });

    $cache->purge() ;

    $term =~ s/^\s*//;
    $term =~ s/\s*$//; 
    $term =~ s/\s+/+/g;

    my $cache_res = $cache->get($term);

    return $cache_res if defined $cache_res;
   
    my $ua  = LWP::UserAgent->new;
    $ua->agent('UDBot/0.001');  
    $ua->timeout(30);

    my $url = sprintf( 'http://www.urbandictionary.com/define.php?term=%s', $term );
    my $res = $ua->get($url);
    
    if ( $res->is_error )  {
        $bot->log( 'error', "Error: ". $res->status_line );
        return;
    }
    
    my $content = decode $res->encoding, $res->content; 

    my $ub_tree = HTML::TreeBuilder::XPath->new;  
    $ub_tree->parse_content($content);  

    my $results = {
        word       => [],
        definition => [],
        examples   => []
    };

    my $xpaths = {
        word       => q|//td[@class="word"]|,
        definition => q|//div[@class="definition"]|,
        examples   => q|//div[@class="example"]| 
    };

    foreach my $key ( keys %{$xpaths} ) {
        foreach my $type ( $ub_tree->findnodes($xpaths->{$key}) ) {
            push @{$results->{$key}}, $type->as_text;
        }
   }
   $cache->set( $term, $results );

   $ub_tree->delete;
    
   return $results;
}

our @COMMANDS = qw| ud |;


1;
