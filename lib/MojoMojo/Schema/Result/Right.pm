package MojoMojo::Schema::Result::Right;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("right");
__PACKAGE__->add_columns(
  "id",
  {
    data_type => "INTEGER",
    default_value => undef,
    is_nullable => 1,
    size => undef,
  },

  "name",
  { data_type => "char", default_value => "NULL", is_nullable => 1, size => 32 },

  "active",
  { data_type => "INTEGER", is_nullable => 0, size => undef, default => 1 },

);
__PACKAGE__->add_unique_constraint("right_unique", ["name"]);
__PACKAGE__->set_primary_key("id");


=head1 NAME

MojoMojo::Schema::Result::Right

=head1 AUTHOR

Daniel Brosseau <dab@catapulse.org>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
