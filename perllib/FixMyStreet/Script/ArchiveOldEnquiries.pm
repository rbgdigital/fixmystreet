package FixMyStreet::Script::ArchiveOldEnquiries;

use strict;
use warnings;
require 5.8.0;

use FixMyStreet;
use FixMyStreet::App;
use FixMyStreet::DB;
use FixMyStreet::Cobrand;
use FixMyStreet::Map;
use FixMyStreet::Email;

sub archive {
    my $problems_2015 = FixMyStreet::DB->resultset('Problem')->search({
        bodies_str => '2237',
        lastupdate => { '<', "2016-01-01 00:00:00" },
        lastupdate => { '>', "2015-01-01 00:00:00" },
        state      => { '!=', 'closed' },
    },
    {
        group_by => ['user_id', 'id']
    });

    while ( my $problem = $problems_2015->next ) {
        send_email_and_close($problem, $problems_2015->result_source->schema);
    }

    my $problems_2014 = FixMyStreet::DB->resultset('Problem')->search({
        bodies_str => '2237',
        lastupdate => { '>', "2015-01-01 00:00:00" },
        state      => { '!=', 'closed' },
    });

    while ( my $problem = $problems_2014->next ) {
        close_report($problem);
    }
}

sub send_email_and_close {
    my ($problem, $schema) = @_;

    my $user = $problem->user;
    my @problems = $user->problems;

    my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker(@problems[0]->cobrand)->new();
    $cobrand->set_lang_and_domain(@problems[0]->lang, 1);
    FixMyStreet::Map::set_map_class($cobrand->map_type);

    my %h = (
      reports => [@problems],
      report_count => scalar(@problems),
      site_name => $cobrand->moniker,
      user => $user,
      cobrand => $cobrand,
    );

    # Send email
    my $email_result = FixMyStreet::Email::send_cron(
        $schema,
        'archive.txt',
        \%h,
        {
            To => [ [ $user->email, $user->name ] ],
        },
        undef,
        undef,
        $cobrand,
        @problems[0]->lang,
    );

    foreach my $p ( @problems ) {
        close_report($p);
    }
}

sub close_report {
    my $problem = shift;
    $problem->update({ state => 'closed' });
}
