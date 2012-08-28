package MusicBrainz::Server::Translation::Attributes;
use Moose;
BEGIN { extends 'MusicBrainz::Server::Translation'; }

with 'MusicBrainz::Server::Role::Translation' => { domain => 'attributes' };

sub l { __PACKAGE__->instance->gettext(@_) }
sub lp { __PACKAGE__->instance->pgettext(@_) }
sub ln { __PACKAGE__->instance->ngettext(@_) }

1;