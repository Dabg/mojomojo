package MojoMojo::Schema::Result::RightToPath;

use strict;
use warnings;

use base 'DBIx::Class';


__PACKAGE__->load_components("Core");
__PACKAGE__->table("right_to_path");
__PACKAGE__->add_columns(
  "pathperm",
       { data_type => "INTEGER", is_nullable => 0, size => undef },
  "right",
       { data_type => "INTEGER", is_nullable => 0, size => undef },
  "allowed",
       { data_type => "INTEGER", is_nullable => 0, size => undef },
);
__PACKAGE__->set_primary_key("pathperm", "right");


#__PACKAGE__->belongs_to('pathperm', "MojoMojo::Schema::Result::PathPermissions", { id => "pathperm"});
__PACKAGE__->belongs_to("right", "MojoMojo::Schema::Result::Right", { id => "right" });

__PACKAGE__->belongs_to('pathperm', "MojoMojo::Schema::Result::PathPermissions",
    { 'foreign.id' => 'self.pathperm' },
    {
        join_type => 'left',
        on_delete => 'SET NULL',
        on_update => 'CASCADE',
    },
);


1;
