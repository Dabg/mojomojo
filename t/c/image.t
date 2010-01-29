#!/usr/bin/perl -w
use Test::More tests => 6;
BEGIN{
    $ENV{CATALYST_CONFIG} = 't/var/mojomojo.yml';
};
use_ok( Catalyst::Test, 'MojoMojo' );

is( request('/badurl/catalyst.png')->code,'404', 'bad prefix_url, do 404' );

# Image in /.static
ok( request('/.static/catalyst.png')->is_success, 'view image in /.static' );
contenttype_is('/.static/catalyst.png', 'image/png', 'show image type' );

# Image in /myfiles (use with Controller::Image and Formatter::File 
# so you can add image any path )
my ( $res, $c ) = ctx_request('/');
$c->config->{'Formatter::Dir'}{whitelisting} = 't/var/files';
$c->config->{'Formatter::Dir'}{prefix_url} = '/myfiles';

ok( request('/myfiles/catalyst.png')->is_success, 'view image in /myfiles' );
contenttype_is('/myfiles/catalyst.png', 'image/png', 'show image type' );
