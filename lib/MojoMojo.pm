package MojoMojo;

use strict;
use Path::Class 'file';

use Catalyst qw/
    ConfigLoader
    Authentication
    Cache
    Session
    Session::Store::Cache
    Session::State::Cookie
    Static::Simple
    SubRequest
    Unicode
    I18N
    Setenv
    Authorization::Roles
    Authorization::Permission
    /;

use Storable;
use Digest::MD5;
use Data::Dumper;
use MRO::Compat;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode ();
use URI::Escape ();
use MojoMojo::Formatter::Wiki;
use Module::Pluggable::Ordered
    search_path => 'MojoMojo::Formatter',
    except      => qr/^MojoMojo::Plugin::/,
    require     => 1;

our $VERSION = '0.999042';

MojoMojo->config->{authentication}{dbic} = {
    user_class     => 'DBIC::Person',
    user_field     => 'login',
    password_field => 'pass'
};
MojoMojo->config->{default_view}='TT';
MojoMojo->config->{'Plugin::Cache'}{backend} = {
    class => "Cache::FastMmap",
    unlink_on_exit => 1,
    share_file => '' . Path::Class::file(
        File::Spec->tmpdir,
        'mojomojo-sharefile-'.Digest::MD5::md5_hex(MojoMojo->config->{home})
    ),
};

__PACKAGE__->config( authentication => {
    default_realm => 'members',
    use_session   => 1,
    realms => {
        members => {
            credential => {
                class               => 'Password',
                password_field      => 'pass',
                password_type       => 'hashed',
                password_hash_type  => 'SHA-1',
            },
            store => {
                class         => 'DBIx::Class',
                user_class    => 'DBIC::Person',
                role_relation => 'roles',
                role_field    => 'name',
            },
        },
    }
});

__PACKAGE__->config('default_model' => "DBIC" );

# __PACKAGE__->config( 'permissions' => {
#     user_class      => 'DBIC::Person',
#     role_class      => 'DBIC::Roles',
#     role_field_name => 'name'
#     admin_role_name => 'Admins',
#     user_field_name => 'login',
#     anonymous_allowed => 1,
#     anonymous_user_name => 'anonymouscoward',
# });

__PACKAGE__->config('Controller::HTML::FormFu' => {
    languages_from_context => 1,
    localize_from_context  => 1,
});


MojoMojo->setup();

# Check for deployed database
my $has_DB = 1;
my $NO_DB_MESSAGE =<<"EOF";

    ***********************************************
    ERROR. Looks like you need to deploy a database.
    Run script/mojomojo_spawn_db.pl
    ***********************************************

EOF
eval { MojoMojo->model('DBIC')->schema->resultset('MojoMojo::Schema::Result::Person')->next };
if ($@ ) {
    $has_DB = 0;
    warn $NO_DB_MESSAGE;
    warn "(Error: $@)";
}

MojoMojo->model('DBIC')->schema->attachment_dir( MojoMojo->config->{attachment_dir}
        || MojoMojo->path_to('uploads') . '' );

sub prepare {
    my $self = shift->next::method(@_);
    if ( $self->config->{force_ssl} ) {
        my $request = $self->request;
        $request->base->scheme('https');
        $request->uri->scheme('https');
    }
    return $self;
}

=head1 NAME

MojoMojo - A Catalyst & DBIx::Class powered Wiki.

=head1 SYNOPSIS

  # Set up database (see mojomojo.conf first)

  ./script/mojomojo_spawn_db.pl

  # Standalone mode

  ./script/mojomo_server.pl

  # In apache conf
  <Location /mojomojo>
    SetHandler perl-script
    PerlHandler MojoMojo
  </Location>

=head1 DESCRIPTION

Mojomojo is a sort of content management system, borrowing many concepts from
wikis and blogs. It allows you to maintain a full tree-structure of pages,
and to interlink them in various ways. It has full version support, so you can
always go back to a previous version and see what's changed with an easy diff
system. There are also a bunch of other features like live AJAX preview while
editing, page tags, built-in fulltext search, image galleries, and RSS feeds
for every wiki page.

To find out more about how you can use MojoMojo, please visit
http://mojomojo.org or read the installation instructions in
L<MojoMojo::Installation> to try it out yourself.


=cut

sub ajax {
    my ($c) = @_;
    return $c->req->header('x-requested-with')
        && $c->req->header('x-requested-with') eq 'XMLHttpRequest';
}

=head2 expand_wikilink

Proxy method for the L<MojoMojo::Formatter::Wiki> expand_wikilink method.

=cut

sub expand_wikilink {
    my $c = shift;
    return MojoMojo::Formatter::Wiki->expand_wikilink(@_);
}

=head2 wikiword

Format a wikiword as a link or as a wanted page, as appropriate.

=cut

sub wikiword {
    return MojoMojo::Formatter::Wiki->format_link(@_);
}

=head2 pref

Find or create a preference key, update it if you pass a value then return the
current setting.

=cut

sub pref {
    my ( $c, $setting, $value ) = @_;

    return unless $setting;

    # Unfortunately there are MojoMojo->pref() calls in
    # MojoMojo::Schema::Result::Person which makes it hard
    # to get cache working for those calls - so we'll just
    # not use caching for those calls.
    return $c->pref_cached( $setting, $value ) if ref($c) eq 'MojoMojo';

    $setting = $c->model('DBIC::Preference')->find_or_create( { prefkey => $setting } );
    if ( defined $value ) {
        $setting->prefvalue($value);
        $setting->update();
        return $value;
    }
    return (
        defined $setting->prefvalue()
        ? $setting->prefvalue
        : ""
    );
}

=head2 pref_cached

Get preference key/value from cache if possible.

=cut

sub pref_cached {
    my ( $c, $setting, $value ) = @_;

    # Already in cache and no new value to set?
    if ( defined $c->cache->get($setting) and not defined $value ) {
        return $c->cache->get($setting);
    }
    # Check that we have a database, i.e. script/mojomojo_spawn_db.pl was run.
    my $row;
    $row = $c->model('DBIC::Preference')->find_or_create( { prefkey => $setting } );

    # Update database
    $row->update( { prefvalue => $value } ) if defined $value;

    my $prefvalue= $row->prefvalue();

    # if no entry in preferences, try get one from config or get default value
    unless ( defined $prefvalue) {

      if ($setting eq 'main_formatter' ) {
        $prefvalue = defined $c->config->{'main_formatter'}
                     ? $c->config->{'main_formatter'}
                     : 'MojoMojo::Formatter::Markdown';
      } elsif ($setting eq 'default_lang' ) {
        $prefvalue = defined $c->config->{$setting}
                     ? $c->config->{$setting}
                     : 'en';
      } elsif ($setting eq 'name' ) {
        $prefvalue = defined $c->config->{$setting}
                     ? $c->config->{$setting}
                     : 'MojoMojo';
      } elsif ($setting eq 'theme' ) {
        $prefvalue = defined $c->config->{$setting}
                     ? $c->config->{$setting}
                     : 'default';
      } elsif ($setting =~ /^(enforce_login|check_permission_on_view)$/ ) {
        $prefvalue = defined $c->config->{'permissions'}{$setting}
                     ? $c->config->{'permissions'}{$setting}
                     : 0;
      } elsif ($setting =~ /^(cache_permission_data|create_allowed|delete_allowed|edit_allowed|view_allowed|attachment_allowed)$/ ) {
        $prefvalue = defined $c->config->{'permissions'}{$setting}
                     ? $c->config->{'permissions'}{$setting}
                     : 1;
      } else {
        $prefvalue = $c->config->{$setting};
      }

    }

    # Update cache
    $c->cache->set( $setting => $prefvalue );

    return $c->cache->get($setting);
}

=head2 fixw

Clean up wiki words: replace spaces with underscores and remove non-\w, / and .
characters.

=cut

sub fixw {
    my ( $c, $w ) = @_;
    $w =~ s/\s/\_/g;
    $w =~ s/[^\w\/\.]//g;
    return $w;
}

sub prepare_action {
    my $c = shift;

    if ($has_DB) {
        $c->next::method(@_);
    }
    else {
        $c->res->status( 404 );
        $c->response->body($NO_DB_MESSAGE);
        return;
    }
}

=head2 prepare_path

We override this method to work around some of Catalyst's assumptions about
dispatching. Since MojoMojo supports page namespaces
(e.g. '/parent_page/child_page'), with page paths that always start with '/',
we strip the trailing slash from $c->req->base. Also, since MojoMojo indicates
actions by appending a '.$action' to the path
(e.g. '/parent_page/child_page.edit'), we remove the page path and save it in
$c->stash->{path} and reset $c->req->path to $action. We save the original URI
in $c->stash->{pre_hacked_uri}.

=cut

sub prepare_path {
    my $c = shift;
    $c->next::method(@_);
    $c->stash->{pre_hacked_uri} = $c->req->uri->clone;
    my $base = $c->req->base;
    $base =~ s|/+$||;
    $c->req->base( URI->new($base) );
    my ( $path, $action );
    $path = $c->req->path;
    my $index = index( $path, '.' );

    if ( $index == -1 ) {

        # no action found, default to view
        $c->stash->{path} = $path || '/';
        $c->req->path('view');
    }
    else {

        # set path in stash, and set req.path to action
        $c->stash->{path} = '/' . substr( $path, 0, $index );
        $c->req->path( substr( $path, $index + 1 ) );
    }
}

=head2 base_uri

Return $c->req->base as an URI object.

=cut

sub base_uri {
    my $c = shift;
    return URI->new( $c->req->base );
}

=head2 uri_for

Override $c->uri_for to append path, if a relative path is used.

=cut

sub uri_for {
    my $c = shift;
    unless ( $_[0] =~ m/^\// ) {
        my $val = shift @_;
        my $prefix = $c->stash->{path} =~ m|^/| ? '' : '/';
        unshift( @_, $prefix . $c->stash->{path} . '.' . $val );
    }

    # do I see unicode here?
    if (Encode::is_utf8($_[0])) {
        $_[0] = join('/', map { URI::Escape::uri_escape_utf8($_) } split(/\//, $_[0]) );
    }

    my $res = $c->next::method(@_);
    $res->scheme('https') if $c->config->{'force_ssl'};
    return $res;
}

sub uri_for_static {
    my ( $self, $asset ) = @_;
    return ( $self->config->{static_path} || '/.static/' ) . $asset;
}


sub check_view_permission {
    my $c = shift;

    return 1 unless $c->pref('check_permission_on_view');

    my $user;
    if ( $c->user_exists() ) {
        $user = $c->user->obj;
    }

    $c->log->info('Checking permissions') if $c->debug;

    my $perms = $c->check_permissions( $c->stash->{path}, $user );
    if ( !$perms->{view} ) {
        $c->stash->{message}
            = $c->loc( 'Permission Denied to view x', $c->stash->{page}->name );
        $c->stash->{template} = 'message.tt';
        return;
    }

    return 1;
}

my $search_setup_failed = 0;

MojoMojo->config->{index_dir} ||= MojoMojo->path_to('index');
MojoMojo->config->{attachment_dir} ||= MojoMojo->path_to('uploads');
unless (-e MojoMojo->config->{index_dir}) {
    if (not mkdir MojoMojo->config->{index_dir}) {
       warn 'Could not make index directory <'.MojoMojo->config->{index_dir}.'> - FIX IT OR SEARCH WILL NOT WORK!';
       $search_setup_failed = 1;
    }
}
unless (-w MojoMojo->config->{index_dir}) {
    warn 'Require write access to index <'.MojoMojo->config->{index_dir}.'> - FIX IT OR SEARCH WILL NOT WORK!';
    $search_setup_failed = 1;
}

MojoMojo->model('Search')->prepare_search_index()
    if not -f MojoMojo->config->{index_dir}.'/segments' and not $search_setup_failed and not MojoMojo->pref('disable_search');

unless (-e MojoMojo->config->{attachment_dir}) {
    mkdir MojoMojo->config->{attachment_dir}
        or die 'Could not make attachment directory <'.MojoMojo->config->{attachment_dir}.'>';
}
die 'Require write access to attachment_dir: <'.MojoMojo->config->{attachment_dir}.'>'
    unless -w MojoMojo->config->{attachment_dir};

1;

=head1 SUPPORT

If you want to talk about MojoMojo, there's an IRC channel, L<irc://irc.perl.org/mojomojo>.
Commercial support and customization for MojoMojo is also provided by Nordaaker
Ltd. Contact C<arneandmarcus@nordaaker.com> for details.

=head1 AUTHORS

Marcus Ramberg C<marcus@nordaaker.com>

David Naughton C<naughton@umn.edu>

Andy Grundman C<andy@hybridized.org>

Jonathan Rockway C<jrockway@jrockway.us>

A number of other contributors over the years:
https://www.ohloh.net/p/mojomojo/contributors


=head1 COPYRIGHT

Copyright 2005-2009, Marcus Ramberg

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
