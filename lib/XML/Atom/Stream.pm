package XML::Atom::Stream;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use Carp;
use LWP::UserAgent;
use XML::SAX::ParserFactory;
use HTTP::Request;

sub new {
    my($class, %param) = @_;
    my $self = bless \%param, $class;
    $self->init();
    $self;
}

sub init {
    my $self = shift;
    $self->{ua} ||= LWP::UserAgent->new(agent => "XML::Atom::Stream/$VERSION");
    $self->{callback} or Carp::croak("no callback specified.");
    $self->{parser} = $self->_setup_parser;
}

sub _setup_parser {
    my $self = shift;
    my $handler = XML::Atom::Stream::SAXHandler->new;
       $handler->{callback} = $self->{callback};
    my $parser  = XML::SAX::ParserFactory->parser( Handler => $handler );
    return $parser;
}

sub connect {
    my($self, $url) = @_;
    $url or Carp::croak("URL needed for connect()");
    $self->{ua}->get($url, ':content_cb' => sub { $self->on_content_cb(@_) });
}

sub on_content_cb {
    my($self, $data, $res, $proto) = @_;
    $self->{parser}->parse_string($data);
}

package XML::Atom::Stream::SAXHandler;
use XML::Handler::Trees;
use HTML::Entities;
use base qw( XML::Handler::Tree );

sub end_element {
    my $self = shift;
    $self->SUPER::end_element(@_);
    my($ref) = @_;
    if ($ref->{LocalName} eq 'feed') {
        my $element = $self->{Curlist};
        my $xml = qq(<?xml version="1.0" encoding="utf-8"?>\n);
        my $dumper;
        $dumper = sub {
            my($ref) = @_;
            my($elem, $stuff) = splice @$ref, 0, 2;
            if ($elem eq '0') {
                $xml .= HTML::Entities::encode($stuff);
            }
            elsif ($elem =~ /^\{(.*?)\}(\w+)$/) {
                my($xmlns, $tag) = ($1, $2);
                my $attr = shift @$stuff;
                $xml .= qq(<$tag);
                $xml .= ' ' . join(' ', map qq($_=") . HTML::Entities::encode($attr->{$_}) . qq("), keys %$attr) if keys %$attr;
                $xml .= qq( xmlns="$xmlns") if $xmlns ne 'http://www.w3.org/2005/Atom';
                if (@$stuff) {
                    $xml .= ">";
                    $dumper->($stuff);
                    $xml .= "</$tag>";
                } else {
                    $xml .= "/>";
                }
            }
            $dumper->($ref) if @$ref;
        };
        $dumper->($element);
        eval { $self->{callback}->($xml) };
        Carp::carp $@ if $@;
    }
}

1;
__END__

=head1 NAME

XML::Atom::Stream - A client interface for AtomStream

=head1 SYNOPSIS

  use XML::Atom::Stream;

  my $url = "http://danga.com:8081/atom-stream.xml";

  my $client = XML::Atom::Stream->new(
      callback => \&callback,
  );
  $client->connect($url);

  sub callback {
      my($xml) = @_;
      my $feed = XML::Atom::Feed->new(Stream => \$xml);
      # Note: you'll need XML::Atom >= 0.12_01 to parse Atom 1.0 feed
  }

=head1 DESCRIPTION

XML::Atom::Stream is a consumer of AtomStream.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt> with tips from
Benjamin Trott and Brad Fitzpatrick.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<XML::Atom>,
L<XML::Atom::Filter>,
http://www.livejournal.com/users/brad/2143713.html

=cut
