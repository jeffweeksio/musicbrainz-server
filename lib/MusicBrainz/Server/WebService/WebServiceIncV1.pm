package MusicBrainz::Server::WebService::WebServiceIncV1;

use Moose;

extends 'MusicBrainz::Server::WebService::WebServiceInc';

has $_ => (
    is  => 'rw',
    isa => 'Int',
    default => 0
) for qw(
          artist track_rels asin rg_type rel_status discs release_events
          counts various_artists tracks
);

override 'get_rel_types' => sub
{
    my $rels = super;

    push @$rels, 'recording' if shift->track_rels;

    return $rels;
};


sub BUILD
{
    my ($self, $args) = @_;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

=head1 COPYRIGHT

Copyright (C) 2009 Robert Kaye

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=cut
