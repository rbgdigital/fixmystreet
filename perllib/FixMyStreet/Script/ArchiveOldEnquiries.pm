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

my $query = {
    bodies_str => { 'LIKE', '%2237%'},
    -and       => [
      lastupdate => { '<', "2016-01-01 00:00:00" },
      lastupdate => { '>', "2015-01-01 00:00:00" },
    ],
    state      => [ FixMyStreet::DB::Result::Problem->open_states() ],
};

sub archive {
    my @user_ids = FixMyStreet::DB->resultset('Problem')->search($query,
    {
        distinct => 1,
        columns  => ['user_id'],
    })->all;

    @user_ids = map { $_->user_id } @user_ids;

    my $users = FixMyStreet::DB->resultset('User')->search({
        id => @user_ids
    });

    while ( my $user = $users->next ) {
        send_email_and_close($user);
    }

    my $problems_2014 = FixMyStreet::DB->resultset('Problem')->search({
        bodies_str => { 'LIKE', '%2237%'},
        lastupdate => { '<', "2015-01-01 00:00:00" },
        state      => [ FixMyStreet::DB::Result::Problem->open_states() ],
    });

    $problems_2014->update({ state => 'closed' });
}

sub send_email_and_close {
    my ($user) = @_;

    my $problems = $user->problems->search($query);

    my @problems = $problems->all;

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
        $problems->result_source->schema,
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

    $problems->update({ state => 'closed' });
}
