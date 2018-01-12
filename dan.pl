#!/usr/bin/env perl
use 5.016;
use warnings;
use strict;

=head1 NAME

  dan.pl - download Danbooru posts by ID, pool, or tag search

=head1 SYNOPSIS

  dan.pl post <id> [<id>]...

  dan.pl pool [--md5] <id>

  dan.pl tags <tag> [<tag>]...

=head1 OPTIONS

=head2 COMMON OPTIONS

=over 4

=item B<-d>=I<dir>, B<--output-dir>=I<dir>

Set the output directory to I<dir>. I<dir> will be created if it does not
exist. Defaults to the current working directory.

=item B<-v>, B<--verbose>

Be more talkative. Displays the MD5 checksum and ID of posts as they finish
downloading. Repeating the option will increase amount of output.

=back

=head2 POOL OPTIONS

=over 4

=item B<--md5>

Save pool posts to files named by MD5 checksum. Default is to name files in
numerical sequence, starting at zero, 0-padded to the same width.

=back

=cut

use Carp;
use File::Path qw(make_path);
use Getopt::Long qw(GetOptionsFromArray :config auto_help gnu_getopt);
use HTTP::Tiny;
use JSON;
use Pod::Usage;
use Readonly;
use Try::Tiny;

Readonly my $SCHEME => 'https';
Readonly my $HOST   => 'danbooru.donmai.us';

Readonly my %MODES => (
  post => \&do_post,
  pool => \&do_pool,
  tags => \&do_tags,
);

Readonly my $PROGRESS => 1;
Readonly my $DEBUG    => 2;

my $auth = $ENV{DANBOORU_AUTH};
my $http;
my $verbose = 0;
my $output_dir = '.';

my %opts = (
  verbose      => \$verbose,
  'output-dir' => \$output_dir,
);

exit main(@ARGV);

sub main {
  # Mode of operation
  my $mode = shift or pod2usage(2);
  croak "unrecognized mode $mode" unless exists $MODES{$mode};
  $mode = $MODES{$mode};

  # Process common options
  GetOptionsFromArray(\@_, \%opts,
    'output-dir|d=s',
    'verbose|v+',
  ) or pod2usage(2);

  say encode_json(\@_) if $verbose >= $DEBUG;

  # chdir to output directory
  make_path($output_dir);
  chdir $output_dir;

  $http = HTTP::Tiny->new;

  goto $mode;
}

sub do_post {
  my (@ids) = @_;

  for my $id (@ids) {
    try {
      my $info = get_post_info($id);
      my $filename = "$info->{md5}.$info->{file_ext}";
      download_file($info->{file_url} => $filename);
    } catch {
      warn "error downloading post $id, $_";
    };
  }
}

sub get_post_info {
  my ($id) = @_;

  my $url = build_url("/posts/$id.json");
  my $resp = $http->get($url);
  assert_request_success($resp);

  return decode_json($resp->{content});
}

sub download_file {
  my ($file_url, $filename) = @_;

  my $resp = $http->mirror(build_url($file_url), $filename);
  assert_request_success($resp);
}

sub build_url {
  my ($endpoint) = @_;

  return defined $auth
    ? "$SCHEME://$auth\@$HOST$endpoint"
    : "$SCHEME://$HOST$endpoint";
}

sub assert_request_success {
  my ($resp) = @_;

  confess "$resp->{status} $resp->{reason}" unless $resp->{success};
}
