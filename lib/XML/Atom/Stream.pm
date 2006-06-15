package XML::Atom::Stream;

use strict;
use vars qw($VERSION);
$VERSION = '0.03';

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
    eval { $self->{parser}->parse_string($data) };
    Carp::carp $@ if $@;
}

package XML::Atom::Stream::SAXHandler;
use XML::Atom::Feed;
use XML::Handler::Trees;
use base qw( XML::Handler::Tree );

sub end_element {
    my $self = shift;
    $self->SUPER::end_element(@_);
    my($ref) = @_;
    if ($ref->{LocalName} eq 'feed') {
        my $element = $self->{Curlist};
        my $xml = qq(<?xml version="1.0" encoding="utf-8"?>\n);
        my %ns;
        my $dumper;
        $dumper = sub {
            my($ref) = @_;
            my($elem, $stuff) = splice @$ref, 0, 2;
            if ($elem eq '0') {
                $xml .= encode_xml($stuff);
            }
            elsif ($elem =~ /^\{(.*?)\}([\w\-]+)$/) {
                my($xmlns, $tag) = ($1, $2);
                my $attr = shift @$stuff;
                $xml .= qq(<$tag);

                my $has_xmlns;

                # extract and replace xmlns declarations
                for my $key (keys %$attr) {
                    if ($key =~ m!^\{http://www\.w3\.org/2000/xmlns/\}([\w\-]+)$!) {
                        my $uri   = delete $attr->{$key};
                        $ns{$uri} = $1;
                        $attr->{"xmlns:$1"} = $uri;
                    }
                }

                for my $key (keys %$attr) {
                    my $attr_key;
                    if ($key =~ /^\{(.*?)\}(\w+)$/) {
                        my($xmlns, $prefix) = ($1, $2);
                        my $ns = $ns{$xmlns} || 'unknown';
                        $attr_key = "$ns:$prefix";
                    } else {
                        $attr_key  = $key;
                        $has_xmlns = 1 if $key eq 'xmlns';
                    }

                    $xml .= qq( $attr_key=") . encode_xml($attr->{$key}) . qq(");
                }

                $xml .= qq( xmlns="$xmlns") if $xmlns ne 'http://www.w3.org/2005/Atom' && !$has_xmlns;

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
        my $feed = XML::Atom::Feed->new(Stream => \$xml);
        eval { $self->{callback}->($feed) };
        Carp::carp $@ if $@;
    }
}

my %Map = ('&' => '&amp;', '"' => '&quot;', '<' => '&lt;', '>' => '&gt;',
           '\'' => '&apos;');
my $RE = join '|', keys %Map;

sub encode_xml {
    my($str, $no_cdata) = @_;
    if (!$no_cdata && $str =~ m/
        <[^>]+>  ## HTML markup
        |        ## or
        &(?:(?!(\#([0-9]+)|\#x([0-9a-fA-F]+))).*?);
                 ## something that looks like an HTML entity.
        /x) {
        ## If ]]> exists in the string, encode the > to &gt;.
        $str =~ s/]]>/]]&gt;/g;
        $str = '<![CDATA[' . $str . ']]>';
    } else {
        $str =~ s!($RE)!$Map{$1}!g;
    }
    $str;
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
      my($atom) = @_;
      # $atom is a XML::Atom::Feed object
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
