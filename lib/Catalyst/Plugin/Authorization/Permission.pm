package Catalyst::Plugin::Authorization::Permission;

use namespace::autoclean;
use Moose;

our $VERSION = '0.01';


sub setup_actions {
     my $c   = shift;
     my $ret = $c->maybe::next::method(@_);

     if ( ! ( 
             defined $c->config->{'permissions'}->{admin_role_name} &&
             defined $c->config->{'permissions'}->{role_members} &&
             defined $c->config->{'permissions'}->{user_field_name} &&
             defined $c->config->{'permissions'}->{anonymous_allowed} &&
             defined $c->auth_realms->{default}->{store}->{config}->{user_class}
            )
        ){
       Catalyst::Exception->throw("Authorization::Permission: All keys are required  !\n" .
                                  " Authorization::Permission:\n" .
                                  "   admin_role_name   : Admins role name\n" .
                                  "   role_members      : RelationShip role_members\n" .
                                  "   user_field_name   : Column Username in user_class\n" .
                                  "   anonymous_allowed   : Anonymous allowed ?\n" .
                                  "   anonymous_user_name : Anonymous user id\n" .
                                  " Plugin::Authentication:\n" .
                                  "   default:\n" .
                                  "     ...\n" .
                                  "     store:\n" .
                                  "       user_class : User class\n" .
                                  "     ...\n"
                                 );
        
     }

     return $ret;
}


#  Permissions are checked prior to most actions, including view if that is
#  turned on in the configuration. The permission system works as follows.
#  1. There is a base set of rules which may be defined in the application
#     config, these are:
#          $c->config->{permissions}{view_allowed} = 1; # or 0
#     similar entries exist for delete, edit, create and attachment.
#     if these config variables are not defined, default is to allow
#     anyone to do anything.
#
#   2. Global rules that apply to everyone may be specified by creating a
#      record with a role-id of 0.
#
#   3. Rules are defined using a combination of path, and role and may be
#      applied to subpages or not.
#
#   4. All rules matching a given user's roles and the current path are used to
#      determine the final yes/no on each permission. Rules are evaluated from
#      least-specific path to most specific. This means that when checking
#      permissions on /foo/bar/baz, permission rules set for /foo will be
#      overridden by rules set on /foo/bar when editing /foo/bar/baz. When two
#      rules (from different roles) are found for the same path prefix, explicit
#      allows override denys. Null entries for a given permission are always
#      ignored and do not effect the permissions defined at earlier level. This
#      allows you to change certain permissions (such as create) only while not
#      affecting previously determined permissions for the other actions. Finally -
#      apply_to_subpages yes/no is exclusive. Meaning that a rule for /foo with
#      apply_to_subpages set to yes will apply to /foo/bar but not to /foo alone.
#      The endpoint in the path is always checked for a rule explicitly for that
#      page - meaning apply_to_subpages = no.

sub _cleanup_path {
    my ( $c, $path ) = @_;
    ## make some changes to the path - We have to do this
    ## because path is not always cleaned up before we get it.
    ## sometimes we get caps, other times we don't. Permissions are
    ## set using lowercase paths.

    ## lowercase the path - and ensure it has a leading /
    my $searchpath = lc($path);

    # clear out any double-slashes
    $searchpath =~ s|//|/|g;

    return $searchpath;
}

sub _expand_path_elements {
     my ( $c, $path ) = @_;
     my $searchpath = $c->_cleanup_path( $path );

     my @pathelements = split '/', $searchpath;

     if ( @pathelements && $pathelements[0] eq '' ) {
         shift @pathelements;
     }

     my @paths_to_check = ('/');

     my $current_path;

     foreach my $pathitem (@pathelements) {
         $current_path .= "/" . $pathitem;
         push @paths_to_check, $current_path;
     }

     return @paths_to_check;
 }

=head2 set_permissions

Sets page permissions.

=cut

sub set_permissions {
    my ($c, $path, $role, $reqparam) = @_;

    $c->forward('validate_perm_edit');

    my @path_elements = $c->_expand_path_elements($path);
    my $current_path = pop @path_elements;


    my @Rights =   map { $reqparam->{$_->name} ? 
                            {
                             right => $_->id,
                             allowed => 1
                            }  : 
                            {
                             right => $_->id,
                             allowed => 0
                            }
                         } 
                         $c->model->resultset('Right')->search();


    my $subpages = $reqparam->{subpages} ? 'yes' : 'no';


    my $params = {
         path => $current_path,
         role => $role->id,
         apply_to_subpages   => $subpages,
         # rights => @Rights, # Sniff Recursive update is not supported over 
                              # relationships of type multi (rights)
    };

    my $model = $c->model->resultset('PathPermissions');

    # when subpages should inherit permissions we actually need to update two
    # entries: one for the subpages and one for the current page
    if ($params->{apply_to_subpages} eq 'yes') {

        # update permissions for subpages
        my $subpage = $model->update_or_create( $params );
        map { $subpage->update_or_create_related( 'rights', $_ ) } @Rights;


        # update permissions for the current page
        $params->{apply_to_subpages} = 'no';

        my $current_page = $model->update_or_create( $params );
        map { $current_page->update_or_create_related( 'rights', $_ ) } @Rights;      
    }
    # otherwise, we must remove the subpages permissions entry and update the
    # entry for the current page
    else {

        # delete permissions for subpages
        my $subpages = $model->search( {
            path              => $current_path,
            role              => $role->id,
            apply_to_subpages => 'yes'
         },
        );

        $subpages->search_related('rights', {})->delete_all;
        $subpages->delete;

        # update permissions and rights for the current page
        my $current_page = $model->update_or_create($params);
        map { $current_page->update_or_create_related( 'rights', $_ ) } @Rights;
    }

    # clear cache
    if ( $c->config->{permissions}->{cache_permission_data} ) {
        $c->cache->remove( 'page_permission_data' );
    }
}

=head2 clear_permissions ( .jsrpc/clear_permissions )

Clears this page permissions for a given role (making permissions inherited).

=cut

sub clear_permissions {
    my ($c, $path, $role) = @_;


    my @path_elements = $c->_expand_path_elements($c->stash->{path});
    my $current_path = pop @path_elements;

    if ($role) {

        # delete permissions for subpages
        my $subpages = $c->model->resultset('PathPermissions')->search( {
            path              => $current_path,
            role              => $role->id
        } );

        $subpages->search_related('rights', {})->delete_all;
        $subpages->delete;


        # clear cache
        if ( $c->config->{permissions}->{cache_permission_data} ) {
            $c->cache->remove( 'page_permission_data' );
        }

    }
}

=head2 get_permissions_data

Return a hashref of path permissions

=cut

sub get_permissions_data {
    my ( $c, $current_path, $paths_to_check, $role_ids ) = @_;

    # default to roles for current user
    $role_ids ||= $c->user_role_ids( $c->user );

    my $permdata;

    ## Now that we have our path elements to check, we have to figure out how we are accessing them.
    ## If we have caching turned on, we load the perms from the cache and walk the tree.
    ## otherwise we pull what we need out of the db.
    # structure:   $permdata{$pagepath} = {
    #                                         admin => {
    #                                                   page => {
    #                                                               create => 'yes',
    #                                                               delete => 'yes',
    #                                                               view => 'yes',
    #                                                               edit => 'yes',
    #                                                               attachment => 'yes',
    #                                                           },
    #                                                   subpages => {
    #                                                               create => 'yes',
    #                                                               delete => 'yes',
    #                                                               view => 'yes',
    #                                                               edit => 'yes',
    #                                                               attachment => 'yes',
    #                                                           },
    #                                                  },
    #                                         users => .....
    #                                     }
    if ( $c->config->{permissions}->{cache_permission_data} ){
        $permdata = $c->cache->get('page_permission_data');
    }

    # If we don't have any permissions data, we have a problem. We need to load it.
    # We have two options here - if we are caching, we will load everything and cache it.
    # If we are not - then we load just the bits we need.
    if ( !$permdata ) {
        # Initialize $permdata as a reference or we end up with an error
        # when we try to dereference it further down.  The error we're avoiding is:
        # Can't use string ("") as a HASH ref while "strict refs"
        $permdata = {};
        
        ## either the data hasn't been loaded, or it's expired since we used it last.
        ## so we need to reload it.
        my $rs =
            $c->model->resultset('PathPermissions')
            ->search( undef, { order_by => 'length(path),role,apply_to_subpages' } );

        # if we are not caching, we don't return the whole enchilada.
        if ( ! $c->config->{permissions}->{cache_permission_data} ) {
            ## this seems odd to me - but that's what the DBIx::Class says to do.
            $rs = $rs->search( { role => $role_ids } ) if $role_ids;
            $rs = $rs->search(
                {
                    '-or' => [
                        {
                            path              => $paths_to_check,
                            apply_to_subpages => 'yes'
                        },
                        {
                            path              => $current_path,
                            apply_to_subpages => 'no'
                        }
                    ]
                }
            );
        }

        my $recordtype;
        while ( my $record = $rs->next ) {
           if ( $record->apply_to_subpages eq 'yes' ) {
             $recordtype = 'subpages';
           }
           else {
             $recordtype = 'page';
           }

           my %rightspath = map{ $_->right->name => $_->allowed == 1 ? 'yes' : 'no' } 
                                  $record->rights ;

           %{ $permdata->{ $record->path }{ $record->role->id }{$recordtype} } =
             %rightspath;
         }
      }

    ## now we re-cache it - if we need to.  # !$c->cache('memory')->exists('page_permission_data')
    if ( $c->config->{permissions}->{cache_permission_data} ) {
        $c->cache->set( 'page_permission_data', $permdata );
    }

    return $permdata;
}
 

sub user_role_ids {
    my ( $c, $user ) = @_;

    ## always use role_id 0 - which is default role and includes everyone.
    my @role_ids = (0);

    my $conf = $c->config->{permissions};

    if ( ref("$user") eq 'Catalyst::Authentication::Store::DBIx::Class::User'){
      my @roles = $user->roles; # Return name of roles
    }
    # User = MojoMojo::Model::DBIC::Person (not authentified )
    elsif ( ref("$user") =~ / $conf->{user_class}/ ){
      @role_ids = map {$_->id} $user->roles;
    }

    # if ( ref($user) ) {

    #   my $relationship_role_members = $conf->{role_members};
    #   push @role_ids, map { $_->role->id } 
    #     $user->$relationship_role_members->all;
    # }

    return @role_ids;
}

sub check_permissions {
    my ( $c, $path, $user ) = @_;

    my @rights = map { $_->name } $c->model->resultset('Right')->search();

    # If admin's member
    return {
            map { $_ => 1 } @rights
    } if ($user && $c->check_user_roles(
             $c->config->{'permissions'}->{'admin_role_name'}));


    # if no user is logged in
    if (not $user) {
      # if anonymous user is allowed
      if ( $c->config->{'permissions'}->{'anonymous_allowed'} ){
        my $anonymous = $c->config->{'permissions'}->{'anonymous_user_name'};
        # get anonymous user for no logged-in users
        $user = $c->model($c->auth_realms->{default}->{store}->{config}->{user_class}) 
          ->search( {
                     $c->config->{'permissions'}->{'user_field_name'}  => $anonymous
                    } 
                  )->first;

        Catalyst::Exception->throw("permissions: Can not find $anonymous in user_class!\n")
            if ( ! $user );
      }
    }

    my @paths_to_check = $c->_expand_path_elements($path);
    my $current_path   = $paths_to_check[-1];

    my @role_ids = $c->user_role_ids( $user );

    my $permdata = $c->get_permissions_data($current_path, \@paths_to_check, \@role_ids);

    # rules comparison hash
    # allow everything by default
     my %rulescomparison = (
                            map { $_ => {
                                        'allowed' => $c->config->{'permissions'}->{$_ . '_allowed'},
                                        'role'    => '__default',
                                        'len'     => 0,
                                       }} @rights
                           );

    ## the outcome of this loop is a combined permission set.
    ## The rule orders are basically based on how specific the path
    ## match is.  More specific paths override less specific paths.
    ## When conflicting rules at the same level of path hierarchy
    ## (with different roles) are discovered, the grant is given precedence
    ## over the deny.  Note that more-specific denies will still
    ## override.
    my $permtype = 'subpages';
    foreach my $i ( 0 .. $#paths_to_check ) {
        my $path = $paths_to_check[$i];
        if ( $i == $#paths_to_check ) {
            $permtype = 'page';
        }
        foreach my $role (@role_ids) {
            if (   exists( $permdata->{$path} )
                && exists( $permdata->{$path}{$role} )
                && exists( $permdata->{$path}{$role}{$permtype} ) )
            {

                my $len = length($path);

                foreach my $perm ( keys %{ $permdata->{$path}{$role}{$permtype} } ) {

                    ## if the xxxx_allowed column is null, this permission is ignored.
                    if ( defined( $permdata->{$path}{$role}{$permtype}{$perm} ) ) {
                        if ( $len == $rulescomparison{$perm}{'len'} ) {
                            if ( $permdata->{$path}{$role}{$permtype}{$perm} eq 'yes' ) {
                                $rulescomparison{$perm}{'allowed'} = 1;
                                $rulescomparison{$perm}{'len'}     = $len;
                                $rulescomparison{$perm}{'role'}    = $role;
                            }
                        }
                        elsif ( $len > $rulescomparison{$perm}{'len'} ) {
                            if ( $permdata->{$path}{$role}{$permtype}{$perm} eq 'yes' ) {
                                $rulescomparison{$perm}{'allowed'} = 1;
                            }
                            else {
                                $rulescomparison{$perm}{'allowed'} = 0;
                            }
                            $rulescomparison{$perm}{'len'}  = $len;
                            $rulescomparison{$perm}{'role'} = $role;
                        }
                    }
                }
            }
        }
    }

    my %perms = map { $_ => $rulescomparison{$_}{'allowed'} } keys %rulescomparison;

    # Fast fix for security issue of attachments being deletable by non-authenticated users
    # Overrides permissions for anonymous users to fix http://mojomojo.ideascale.com/akira/dtd/22284-2416
    # TODO "attachment" is a rather vague permission: it seems to apply to creating, editing and deleting attachments
#    @perms{'attachment', 'delete'} = (0, 0) if not $user;

    return \%perms;
}


__PACKAGE__->meta->make_immutable;
__PACKAGE__;

__END__

=pod

=head1 NAME

Catalyst::Plugin::Authorization::Permission - Permissions support for Catalyst applications.

=head1 SYNOPSIS

        use Catalyst qw/
                Authentication
                Authorization::Roles
                Authorization::Permission
        /;

        __PACKAGE__->config(default_model) = 'DBIC'; # ( to search user )

        __PACKAGE__->setup;

        __PACKAGE__->config( 'permissions' => {
                                          admin_role_name     => 'Adminis',
                                          role_members        => 'role_members',
                                          user_field_name     => 'login',
                                          anonymous_allowed   => 1,
                                          anonymous_user_name => 'anonymouscoward',
        });



=head1 DESCRIPTION

This module provides permission path protection.


=head2 allow_access


=head1 SEE ALSO

L<Catalyst::Plugin::Authentication>, L<Catalyst::Plugin::Authorization::Roles>,
L<http://catalyst.perl.org/calendar/2005/24>

=head1 AUTHOR

Daniel Brosseau, C<< <dab at catapulse.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Daniel Brosseau, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Catalyst::Plugin::Authorization::Permission
