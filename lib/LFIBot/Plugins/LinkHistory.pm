package LFIBot::Plugins::LinkHistory;

=pod

=head1 NAME

    LFIBot::Plugins::LinkHistory

=head1 DESCRIPTION

   Plugin to record http urls and them by channel and user

=head1 Exports

=head2 Commands

=over 4

=item  links

    ( user|channel|id:## ) [ like {string} or ... ] [ limit ## ] [ verbose ] 

=back

=head2 Triggers

=over 4

=item  link_history

    Trigged by http urls. It will request the link headers to get the
    page title and then save the server, channel, user, url and page
    title in the database

=back 

=head2 Startup Hooks

=over 4

=item setup link history schema 

    Ensure all tables are created

=back

=cut


use strict;
use warnings;
use base qw| LFIBot::Plugin |;
use Data::Dumper;
use POE;
 
my $startup_hook = {   
    hook => sub {
       my ($bot) = @_; 

       $bot->{dbh}->do("CREATE TABLE IF NOT EXISTS `users`( 
           `id`  INTEGER PRIMARY KEY AUTOINCREMENT,
           `name` VARCHAR(40) NOT NULL,
           `server` VARCHAR(40) NOT NULL, 
           UNIQUE ( name, server )
       )" ); 

       $bot->{dbh}->do("CREATE TABLE IF NOT EXISTS `channels`( 
           `id`  INTEGER PRIMARY KEY AUTOINCREMENT,
           `name` VARCHAR(40) NOT NULL,
           `server` VARCHAR(40) NOT NULL, 
           UNIQUE ( name , server )
       )" );  
    
       $bot->{dbh}->do("CREATE TABLE IF NOT EXISTS `links`( 
           `id`  INTEGER PRIMARY KEY AUTOINCREMENT,
           `url_md5base64` VARCHAR(40) NOT NULL,
           `url` VARCHAR(40) NOT NULL, 
           'title' VARCHAR(80) NOT NULL,  
           UNIQUE (url_md5base64)
       )" );    

       $bot->{dbh}->do("CREATE TABLE IF NOT EXISTS `user_channel_links`( 
           `id`  INTEGER PRIMARY KEY AUTOINCREMENT,
           `user_id` VARCHAR(40) NOT NULL,
           `channel_id` VARCHAR(40) NOT NULL, 
           'link_id' VARCHAR(80) NOT NULL,
           'last_linked' TEXT NOT NULL,
           UNIQUE ( user_id, channel_id, link_id )
       )" ); 

    },
    name     => 'setup link history schema',
    priority => 1
};    

my $link_trigger = {  
    name    => 'link_history', 
    pattern => qr/(https?:\/\/[^\s]+)/,
    process => sub {
        my ( $struct ) = @_;      
        print "link_history trigger hit\n";
        my @urls = $struct->{message} =~ /(https?:\/\/[^\s]+\.[^\s]+)/g;

        $struct->{urls} = \@urls;
        print Dumper $struct;
        #my $struct = {
        #    urls  => \@urls,
        #    who   => $who,
        #    where => $where,
        #    bot   => $bot
        #};

        __PACKAGE__->get_update_urls($struct);

    }
};

sub get_update_urls {
    my ( $class, $struct ) = @_;

    # This is probably  bad 
    $SIG{CHLD} = 'IGNORE';

    fork and return;

    $poe_kernel->has_forked();

    $struct->{bot}->db_reset();

    eval {
        require Encode;
        require HTTP::Response::Encoding;
        HTTP::Response::Encoding->import(); 
        require LWP::UserAgent;
        LWP::UserAgent->import();
        require HTML::HeadParser;
        HTML::HeadParser->import();
        require Digest::MD5;
        Digest::MD5->import(qw| md5_base64 |);
    };
    if ($@) {
        $struct->{bot}->log( 'error', "link_history error: $@\n" );
        exit;
    }

    my $dbh = $struct->{bot}->{dbh};
    $dbh->{AutoCommit} = 0;

    my $ua = LWP::UserAgent->new;
    $ua->default_header( Range => 'bytes=0-8192');
    $ua->agent('LinkHistory/0.001'); 
    $ua->timeout(30);

    my $server_name = $struct->{bot}->server_name;

    foreach my $url ( @{$struct->{urls}} ) {
        my $response = $ua->get($url);

        my $base64_url = md5_base64($url);

        my $title;
        if ( $response->is_success ) {
            
            my $encoding = $response->encoding || 'utf-8';

            my $content = Encode::decode $encoding, $response->content; 

            # Even though I think HTTP::Response should already
            # be doing this to populate the ->title accessor this
            # is much more reliable 
            my $p = HTML::HeadParser->new;

            $p->parse( $content ); 

            $title = $p->header('Title') || 'no title' ;
        }
        else {
            $title = $response->status_line;
        }
        
        my @update_queries = (
            { query =><<END,
                INSERT or IGNORE into 
                    users( name, server )
                 VALUES
                    (?,?)
END
              params => [ $struct->{who}, $server_name ]
            },
            { query =><<END, 
                INSERT or IGNORE into 
                    channels( name, server )
                VALUES
                    (?,?)
END
              params => [ $struct->{channel}, $server_name ]
            },
            { query =><<END,
                INSERT or IGNORE into 
                    links( url_md5base64, url, title )
                VALUES
                    (?,?,?)   
END
              params => [ $base64_url, $url, $title ]
            },
            { query =><<END,
                INSERT or IGNORE into 
                  user_channel_links( user_id, channel_id, link_id, last_linked ) 
                    SELECT 
                      users.id        as user_id,
                      channels.id     as channel_id,
                      links.id        as link_id,
                      datetime('now') as last_linked 
                    FROM  
                      users
                    JOIN
                      channels 
                    JOIN 
                      links 
                    WHERE 
                      channels.name=? and channels.server=?
                        and
                      users.name=? and users.server=?
                        and 
                      links.url_md5base64=?
END
              params => [ $struct->{channel}, $server_name, $struct->{who}, 
                          $server_name, $base64_url ]
            },
            # this sucks but I dont know a way around it without 
            # INSERT or UPDATE that other rdms's have       
            { query =><<END,
                UPDATE 
                  user_channel_links
                SET   
                  last_linked=datetime('now')
                WHERE channel_id=( 
                      SELECT 
                        id
                      FROM
                        channels
                      WHERE name=? and server=? )
                    and
                  user_id=( 
                      SELECT 
                        id
                      FROM
                        users
                      WHERE name=? and server=? ) 
                    and 
                  link_id=( 
                     SELECT 
                        id
                     FROM
                        links
                     WHERE url_md5base64=? ) 
END
              params => [ $struct->{channel}, $server_name, $struct->{who}, 
                          $server_name, $base64_url ] 
            }
        );

        $dbh->do('BEGIN EXCLUSIVE');

        foreach my $update_query (@update_queries) {
            $dbh->do( $update_query->{query}, undef, @{$update_query->{params}} )
                or do {
                        $struct->{bot}->log( 'error', "error on: ". $update_query->{query} );
                        $struct->{bot}->log( 'error', "Error: ". $dbh->errstr );
                        $dbh->do('ROLLBACK');
                        exit;
                   }
        }
        
        $dbh->do('COMMIT'); 

    }

    exit();
}   

sub links {
    my ( $self, $bot, $struct ) = @_; 

    my $search_struct = $self->_link_history_cmd_parse($struct->{args});

    if ( $search_struct->{error} ) {
        $bot->log( 'error', $search_struct->{error} );
        return;
    }

    my $channel_max_limit = 5;

    if ( !defined $struct->{admin_call} ) {
        # Only admins can search history for another 
        # channel
        if ( ( $search_struct->{channel} )
          && ( $search_struct->{channel} ne $struct->{channel} )
        ) {
            return;
        }
        # Set channel to current channel
        if ( !$search_struct->{channel} ) {
             $search_struct->{channel} = $struct->{channel}
        }
        # only admins can get history outside of a
        # channel
        if ( !$struct->{channel}) {
            return;
        }
    }

    my $kind = do {
        if ( $search_struct->{user} && $search_struct->{channel} ) {
            'user_channel'
        }
        elsif ( $search_struct->{user} ) {
            'user'
        }
        elsif ( $search_struct->{'link_id'} ) {
            'link'
        }
        elsif ( $search_struct->{stats} && $search_struct->{channel} ) {
            'user_channel_stats'
        }
        else {
            'channel'
        }
    };

    # Implicit verbose on id lookup 
    if ( $kind eq 'link' ) {
        $search_struct->{verbose} = 1;
    }

    # Never let the bot spam the channel
    if ( $struct->{channel}  
      && ( $search_struct->{limit} > $channel_max_limit )   
    ) {
        $search_struct->{limit} = $channel_max_limit
    }

    my ($lookup_query, $bind_params) =
        $self->_links_compile_query($kind, $search_struct, $bot->server_name );

    $lookup_query or return;

    my $dbh = $bot->{dbh};

    my $sth = $dbh->prepare($lookup_query)  
        or do { $bot->log( 'error', "db err in link history :". $dbh->errstr ); return };
    
    $sth->execute(@{$bind_params})
        or do { $bot->log( 'error', "db err in link history :". $dbh->errstr ); return }; 

    if ( $kind eq 'user_channel_stats' ) {
        my $message = 'top linkers: ';
        while ( my ( $user, $sum ) = $sth->fetchrow_array ) { 
            $message .= sprintf('%s (%i) ', $user, $sum)
        }

        if ( $struct->{channel} ) {
            $bot->message( $struct->{channel_raw}, $message )
        }
        else {
            $bot->message( $struct->{who_raw},  $message ) 
        }

    }
    else {
        while ( my ( $user, $channel, $id, $date, $link, $title ) = $sth->fetchrow_array ) {
            my $message = do {
                if ( $search_struct->{verbose} ) {
                    sprintf('id:%s %s linked %s "%s" in %s on %s',
                        $id,
                        $user,
                        $link,
                        $title,
                        $channel,
                        $date
                    );
                }
                else {
                    sprintf('id:%s %s "%s"',
                        $id,
                        $link,
                        $title,
                    ); 
                }
            };

            if ( $struct->{channel} ) {
                $bot->message( $struct->{channel_raw}, $message )
            }
            else {
                $bot->message( $struct->{who_raw},  $message ) 
            }  
        }
    }
}

sub _link_history_cmd_parse { 
    my ( $self, $arg_string ) = @_;

    my $search_struct = {
        link_id => '',
        user    => '',
        channel => '',
        filters => [],
        limit   => 5,
        verbose => 0,
        stats   => 0
    };
    
    $arg_string =~ s/^\s+//;

    my @tokens = split(/\s+/, $arg_string);

    my $search_token = do {
        if ( $tokens[0] ) {
            if ( $tokens[0] =~ /^#/ ) {
                'channel'
            }
            elsif ( $tokens[0] =~ /^id\:[0-9]+$/ ) {
                'link_id'
            }
            else {
                'user'
            }
        }
        else {
            ''
        }
    };

    if ( $search_token ) {

        $search_struct->{$search_token} = shift @tokens;

        if ( ( $search_token eq 'user' ) && $tokens[0] && ( $tokens[0] eq 'in' ) ) {

            shift @tokens;
            my $channel = shift @tokens;
            
            if ( $channel !~ /^#/ ) {
                $search_struct->{error} = 'invalid channel';
                return $search_struct;
            }
            $search_struct->{channel} = $channel;
        }
        elsif ( $search_token eq 'link_id' ) {
             $search_struct->{$search_token} =~ s/^id\://;
        }
    }

TOKEN_PARSE_LOOP:
    while ( my $token = shift @tokens ) {
        
        if ( $token eq 'like' ) {
        LIKE_PARSE_LOOP:
            while ( my $like_token = shift @tokens ) {
                if (!$like_token) {
                    $search_struct->{error} = 'invalid like';
                    return $search_struct; 
                }

                push @{$search_struct->{filters}},  $like_token;

                if ( $tokens[0] && $tokens[0] ne 'or' ) {
                    last LIKE_PARSE_LOOP;
                }
                else {
                    shift @tokens;
                }
            }
        }
        elsif ( $token eq 'limit' ) {
            my $val = shift @tokens; 
            if ( $val !~ /^[0-9]+$/ ) {
                $search_struct->{error} = 'invalid limit';
                return $search_struct;
            }

            $search_struct->{limit} = $val;

        }
        elsif ( $token eq 'verbose' ) {
            $search_struct->{verbose} = 1
        }
        elsif ( $token eq 'stats' ) {
            $search_struct->{stats} = 1 
        }
        else {
            $search_struct->{error} = "invalid parameter: $token";
            return $search_struct; 
        }
    }
    return $search_struct;

}  

sub _link_query_type_templates {
    my ( $self, $search_struct ) = @_;

    my $queries = {};
    $queries->{user} =<<"END";
        SELECT
            users.name                     as user,
            channels.name                  as channel,
            user_channel_links.id          as id, 
            user_channel_links.last_linked as date,
            links.url                      as url,
            links.title                    as title
        FROM
            users
        JOIN
            user_channel_links
        ON
            user_channel_links.user_id=users.id
        JOIN
            links
        ON
            user_channel_links.link_id=links.id
        JOIN
            channels
        ON
            user_channel_links.channel_id=channels.id
        WHERE
            users.name=?
              and 
            users.server=?
              and
            channels.server=?
END

    $queries->{channel} =<<"END";
        SELECT
            users.name                     as user,
            channels.name                  as channel,
            user_channel_links.id          as id, 
            user_channel_links.last_linked as date, 
            links.url                      as url,
            links.title                    as title
        FROM
            channels
        JOIN
            user_channel_links
        ON
            user_channel_links.channel_id=channels.id
        JOIN
            links
        ON
            user_channel_links.link_id=links.id
        JOIN
            users
        ON
            user_channel_links.user_id=users.id
        WHERE
            channels.name=?
              and 
            channels.server=?
              and
            users.server=?
END

    $queries->{user_channel} =<<"END";
        SELECT
            users.name                     as user,
            channels.name                  as channel,
            user_channel_links.id          as id, 
            user_channel_links.last_linked as date, 
            links.url                      as url,
            links.title                    as title
        FROM
            users
        JOIN
            user_channel_links
        ON
            user_channel_links.user_id=users.id
        JOIN
            links
        ON
            user_channel_links.link_id=links.id
        JOIN
            channels
        ON
            user_channel_links.channel_id=channels.id
        WHERE
            users.name=?
              and
            users.server=?  
              and 
            channels.name=?
              and
            channels.server=?
            
END

    $queries->{'link'} =<<"END";
        SELECT
            users.name                     as user,
            channels.name                  as channel,
            user_channel_links.id          as id,
            user_channel_links.last_linked as date, 
            links.url                      as url,
            links.title                    as title
        FROM
            user_channel_links
        JOIN
            users
        ON
            users.id=user_channel_links.user_id
        JOIN
            links
        ON
            user_channel_links.link_id=links.id
        JOIN
            channels
        ON
            channels.id=user_channel_links.channel_id
        WHERE
            user_channel_links.id=?
              and
            users.server=?  
              and
            channels.server=? 
END

    $queries->{user_channel_stats} =<<"END";
        SELECT
            users.name                     as user,
            count(user_channel_links.id)   as total_links 
        FROM
            channels
        JOIN
            user_channel_links
        ON
            user_channel_links.channel_id=channels.id
        JOIN
            users
        ON
            user_channel_links.user_id=users.id
        JOIN
            links
        ON
            user_channel_links.link_id=links.id  
        WHERE
            channels.name=?
              and 
            channels.server=?
              and
            users.server=?  
END
    
    

    my $group_by = {};

    $group_by->{user_channel_stats} = 'user'; 

    return ( $queries, $group_by );

}

sub _links_compile_query {
    my ( $self, $kind, $search_struct, $server_name ) = @_;

    my ( $query_templates, $group_by ) =
        $self->_link_query_type_templates($search_struct);
    
    my $bind_params = {};
    $bind_params->{user}               = [ $search_struct->{user},
                                           $server_name, $server_name  ];
    $bind_params->{channel}            = [ $search_struct->{channel}, 
                                           $server_name, $server_name ]; 
    $bind_params->{user_channel_stats} = $bind_params->{channel};

    $bind_params->{user_channel}  = [ $search_struct->{user}, $server_name, 
                                      $search_struct->{channel}, $server_name ];  

    $bind_params->{'link'}        = [ $search_struct->{link_id},  
                                       $server_name, $server_name ];   

    return unless ( defined $query_templates->{$kind} && defined $bind_params->{$kind} ); 
    
    my $lookup_query = $query_templates->{$kind};

    if ( @{ $search_struct->{filters} } > 0 ) {
        
        $lookup_query .= sprintf('and ( %s )', 
                            join(' or ', 
                               map { 
                                 'links.url like ?'
                               } @{ $search_struct->{filters} }  
                            ) 
                         );
    }
    push @{ $bind_params->{$kind} }, map { "%$_%"  } @{ $search_struct->{filters} }; 
    
    if ( $search_struct->{stats} ) {
        
        $lookup_query .= sprintf(' GROUP BY %s', $group_by->{$kind} );   
        $lookup_query .= ' ORDER BY total_links DESC ';  

    }
    else {
        $lookup_query .= ' ORDER BY date DESC '; 
    }

    push @{ $bind_params->{$kind} }, $search_struct->{limit};

    $lookup_query .= sprintf(' LIMIT ?', $search_struct->{limit} );  

    return ( $lookup_query, $bind_params->{$kind} );  

} 

our @STARTUP  = ( $startup_hook );
our @TRIGGERS = ( $link_trigger );
our @COMMANDS = qw| links |;

1;
