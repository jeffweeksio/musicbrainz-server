package MusicBrainz::Server::Controller::WS::2::Recording;
use Moose;
BEGIN { extends 'MusicBrainz::Server::ControllerBase::WS::2' }

use aliased 'MusicBrainz::Server::Buffer';
use aliased 'MusicBrainz::Server::WebService::WebServiceStash';
use Function::Parameters 'f';
use MusicBrainz::Server::Constants qw(
    $EDIT_RECORDING_ADD_PUIDS
);
use MusicBrainz::Server::WebService::XMLSearch qw( xml_search );
use Readonly;

my $ws_defs = Data::OptList::mkopt([
     recording => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ],
     },
     recording => {
                         method   => 'GET',
                         linked   => [ qw(artist release) ],
                         inc      => [ qw(artist-credits puids isrcs
                                          _relations tags user-tags ratings user-ratings) ],
                         optional => [ qw(limit offset) ],
     },
     recording => {
                         method   => 'GET',
                         inc      => [ qw(artists releases artist-credits puids isrcs aliases
                                          _relations tags user-tags ratings user-ratings) ]
     },
     recording => {
                         method => 'POST'
     },
]);

with 'MusicBrainz::Server::WebService::Validator' =>
{
     defs => $ws_defs,
};

with 'MusicBrainz::Server::Controller::Role::Load' => {
    model => 'Recording'
};

Readonly our $MAX_ITEMS => 25;

sub base : Chained('root') PathPart('recording') CaptureArgs(0) { }

sub recording_toplevel
{
    my ($self, $c, $stash, $recording) = @_;

    my $opts = $stash->store ($recording);

    $self->linked_recordings ($c, $stash, [ $recording ]);

    if ($c->stash->{inc}->releases)
    {
        my @results;
        if ($c->stash->{inc}->media)
        {
            @results = $c->model('Release')->load_with_tracklist_for_recording(
                $recording->id, $MAX_ITEMS, 0, $c->stash->{status}, $c->stash->{type});
        }
        else
        {
            @results = $c->model('Release')->find_by_recording(
                $recording->id, $MAX_ITEMS, 0, $c->stash->{status}, $c->stash->{type});
        }

        $self->linked_releases ($c, $stash, $results[0]);

        $opts->{releases} = $self->make_list (@results);
    }

    if ($c->stash->{inc}->artists)
    {
        $c->model('ArtistCredit')->load($recording);

        my @artists = map { $c->model('Artist')->load ($_); $_->artist } @{ $recording->artist_credit->names };

        $self->linked_artists ($c, $stash, \@artists);
    }

    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $recording);
    }
}

sub recording: Chained('load') PathPart('')
{
    my ($self, $c) = @_;
    my $recording = $c->stash->{entity};

    my $stash = WebServiceStash->new;

    $self->recording_toplevel ($c, $stash, $recording);

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('recording', $recording, $c->stash->{inc}, $stash));
}

sub recording_browse : Private
{
    my ($self, $c) = @_;

    my ($resource, $id) = @{ $c->stash->{linked} };
    my ($limit, $offset) = $self->_limit_and_offset ($c);

    if (!MusicBrainz::Server::Validation::IsGUID($id))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $recordings;
    my $total;
    if ($resource eq 'artist')
    {
        my $artist = $c->model('Artist')->get_by_gid($id);
        $c->detach('not_found') unless ($artist);

        my @tmp = $c->model('Recording')->find_by_artist ($artist->id, $limit, $offset);
        $recordings = $self->make_list (@tmp, $offset);
    }
    elsif ($resource eq 'release')
    {
        my $release = $c->model('Release')->get_by_gid($id);
        $c->detach('not_found') unless ($release);

        my @tmp = $c->model('Recording')->find_by_release ($release->id, $limit, $offset);
        $recordings = $self->make_list (@tmp, $offset);
    }

    my $stash = WebServiceStash->new;

    for (@{ $recordings->{items} })
    {
        $self->recording_toplevel ($c, $stash, $_);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('recording-list', $recordings, $c->stash->{inc}, $stash));
}

sub recording_search : Chained('root') PathPart('recording') Args(0)
{
    my ($self, $c) = @_;

    $c->detach('recording_submit') if $c->req->method eq 'POST';
    $c->detach('recording_browse') if ($c->stash->{linked});

    my $result = xml_search('recording', $c->stash->{args});
    $self->_search ($c, 'recording');
}

sub recording_submit : Private
{
    my ($self, $c) = @_;

    my $client = $c->req->query_params->{client}
        or _error($c, 'You must provide information about your client, by the client query parameter');

    my $xp = XML::XPath->new( xml => $c->request->body );

    my %submit;
    for my $node ($xp->find('/metadata/recording-list/recording')->get_nodelist)
    {
        my $id = $node->getAttribute('id') or
            _error ($c, "All releases must have an MBID present");

        _error($c, "$id is not a valid MBID")
            unless MusicBrainz::Server::Validation::IsGUID($id);

        my @puids = $node->find('puid-list/puid')->get_nodelist;
        for my $puid_node (@puids) {
            my $puid = $puid_node->getAttribute('id');
            _error($c, "$puid is not a valid PUID")
                unless MusicBrainz::Server::Validation::IsGUID($puid);

            $submit{ $id } ||= [];
            push @{ $submit{$id} }, $puid;
        }
    }

    my %recordings_by_id = %{ $c->model('Recording')->get_by_gids(keys %submit) };
    my %recordings_by_gid = map { $_->gid => $_->id } values %recordings_by_id;

    my @submissions;
    for my $recording_gid (keys %submit) {
        _error($c, "$recording_gid does not match any known recordings")
            unless exists $recordings_by_gid{$recording_gid};
    }

    my $buffer = Buffer->new(
        limit => 100,
        on_full => f($contents) {
            my $new_rows = $c->model('RecordingPUID')->filter_additions(@$contents);
            return unless @$new_rows;

            $c->model('Edit')->create(
                edit_type      => $EDIT_RECORDING_ADD_PUIDS,
                editor_id      => $c->user->id,
                client_version => $client,
                puids          => $new_rows
            );
        }
    );

    $buffer->flush_on_complete(sub {
        for my $recording_gid (keys %submit) {
            $buffer->add_items(map +{
                recording_id => $recordings_by_gid{$recording_gid},
                puid         => $_
            }, @{ $submit{$recording_gid} });
        }
    });

    $c->detach('success');
}

__PACKAGE__->meta->make_immutable;
1;

