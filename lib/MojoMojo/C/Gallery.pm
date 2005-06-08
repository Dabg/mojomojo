package MojoMojo::C::Gallery;

use strict;
use base 'Catalyst::Base';

=head1 NAME

MojoMojo::C::Gallery - Catalyst component

=head1 SYNOPSIS

See L<MojoMojo>

=head1 DESCRIPTION

Catalyst component.

=head1 METHODS

=over 4

=item default

=cut

sub default : Private {
    my ( $self, $c, $action, $page) = @_;
    $c->stash->{template} = 'gallery.tt';
    # oops, we have a column value named Page
    # FIXME : Messing with the iterator.
    my ($pager,$iterator) =MojoMojo::M::Core::Attachment->pager( 
                     page=>$c->stash->{page},
             { page =>$page || 1,
              rows => 12,
            });
    $iterator->{_class}='MojoMojo::M::Core::Photo';
    $c->stash->{pictures} = $iterator;
    $c->stash->{pager} = $pager;
}

sub p : Global {
    my ( $self, $c, $photo ) = @_;
    $c->stash->{template}='gallery/photo.tt';
    $c->stash->{photo}= MojoMojo::M::Core::Photo->retrieve($photo);
}

=item submittag (/gallery/submittag)

Add a tag through form submit

=cut

sub submittag : Local {
    my ( $self, $c, $photo ) = @_;
    $c->req->args( [ $photo,$c->req->params->{tag} ] );
    $c->forward('tag');
}

=item tag (/.jsrpc/tag)

add a tag to a page. return list of yours and popular tags.

=cut

sub tag : Local {
    my ( $self, $c,$photo, $tagname ) = @_;
    ($tagname)= $tagname =~ m/(\w+)/;
    unless (
        ! $tagname ||
        MojoMojo::M::Core::Tag->search(
            photo   => $photo,
            person => $c->stash->{user},
            tag    => $tagname
        )->next()
      ) {
        MojoMojo::M::Core::Tag->create(
            {
                photo  => $photo,
                tag    => $tagname,
                person => $c->stash->{user}
            }
          )
          if $photo;
    }
    $c->stash->{photo}=$photo;
    $c->req->args( [ $tagname ] );
    $c->forward('tags');
}

=item untag (/.jsrpc/untag)

remove a tag to a page. return list of yours and popular tags.

=cut

sub untag : Local {
    my ( $self, $c, $photo, $tagname ) = @_;
    my $tag = MojoMojo::M::Core::Tag->search(
        photo   => $photo,
        person => $c->stash->{user},
        tag    => $tagname
    )->next();
    $tag->delete() if $tag;
    $c->stash->{photo}=$photo;
    $c->req->args( [ $tagname ] );
    $c->forward('tags');
}


sub tags : Local {
    my ( $self, $c, $highlight ) = @_;
    $c->stash->{template}  = 'gallery/tags.tt';
    $c->stash->{highlight} = $highlight;
    my $photo=$c->stash->{photo};
    $photo=MojoMojo::M::Core::Photo->retrieve($photo) unless ref $photo;
    $c->stash->{photo}=$photo;
    $c->log->info('user is '.$c->req->{user_id});
    if ($c->req->{user}) {
    my @tags = $photo->others_tags( $c->req->{user_id});
    $c->stash->{others_tags} = [@tags];
    @tags                    = $photo->user_tags( $c->stash->{user} );
    $c->stash->{taglist}     = ' ' . join( ' ', map { $_->tag } @tags ) . ' ';
    $c->stash->{tags}        = [@tags];
    } else {
      $c->stash->{others_tags}      = [ $photo->tags ];
    }
}

sub description : Local { 
    my ( $self, $c, $photo ) = @_;
    $c->form(required=>[qw/description/]);
    my $img=MojoMojo::M::Core::Photo->retrieve($photo);
    unless ($c->form->has_missing && $c->form->has_invalid ) {
      $img->update_from_form($c->form);
    }
      $c->res->body('<em>updated ok</em>');
}

sub title : Local { 
    my ( $self, $c, $photo ) = @_;
    $c->form(required=>[qw/title/]);
    my $img=MojoMojo::M::Core::Photo->retrieve($photo);
    unless ($c->form->has_missing && $c->form->has_invalid ) {
      $img->update_from_form($c->form);
    }
      $c->res->body('<em>updated ok</em>');
}

=back

=head1 AUTHOR

Marcus Ramberg <mramberg@cpan.org>

=head1 LICENSE

This library is free software . You can redistribute it and/or modify 
it under the same terms as perl itself.

=cut

1;
