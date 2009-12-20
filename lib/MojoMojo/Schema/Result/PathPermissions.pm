package MojoMojo::Schema::Result::PathPermissions;

use strict;
use warnings;
use Data::Dumper;

use parent qw/MojoMojo::Schema::Base::Result/;

__PACKAGE__->load_components( "Core" );
__PACKAGE__->table("path_permissions");
__PACKAGE__->add_columns(
    "id",
    {
        data_type         => "INTEGER",
        is_nullable       => 0,
        size              => undef,
        is_auto_increment => 1
    },
    "path",               { data_type => "VARCHAR", is_nullable => 0, size => 255 },
    "role",               { data_type => "INTEGER", is_nullable => 0, size => undef },
    "apply_to_subpages",  { data_type => "VARCHAR", is_nullable => 0, size => 3 },
);

__PACKAGE__->set_primary_key( 'id' );
__PACKAGE__->add_unique_constraint(  path_role_subpages => [ qw /path role apply_to_subpages/ ] );
__PACKAGE__->belongs_to( "role", "MojoMojo::Schema::Result::Role", { id => "role" } );
__PACKAGE__->has_many (  rights => 'MojoMojo::Schema::Result::RightToPath', 'pathperm');





=head1 NAME

MojoMojo::Schema::Result::PathPermissions

=head1 AUTHOR

Marcus Ramberg <mramberg@cpan.org>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


1;
