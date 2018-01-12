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
use POSIX qw(ceil);
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

Readonly my $POSTS_PER_PAGE => 20;

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
    'md5',
  ) or pod2usage(2);

  say 'ARGV: ', encode_json(\@_) if show_debug();

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
      say "downloading post $id" if show_progress();
      my $info = get_post_info($id);
      my $filename = "$info->{md5}.$info->{file_ext}";
      download_file($info->{file_url} => $filename);
    } catch {
      warn "error downloading post $id, $_";
    };
  }
}

sub do_pool {
  my ($id) = @_;

  say "downloading pool $id" if show_progress();

  my $info = get_pool_info($id);
  my @post_ids = split / /, $info->{post_ids};

  # sub for determining filename
  my $build_basename;
  my $index = 0;
  if ($opts{md5}) {
    $build_basename = sub { $_[0]->{md5} };
  } else {
    my $width = length($#post_ids);  # zero-indexed, so we only go up to n-1
    $build_basename = sub { pad_number($width, $index) };
  }

  for my $id (@post_ids) {
    try {
      say "downloading post $id" if show_progress();
      my $info = get_post_info($id);
      my $filename = $build_basename->($info) . ".$info->{file_ext}";
      download_file($info->{file_url} => $filename);
    } catch {
      warn "error downloading post $id, $_";
    };

    $index++;
  }
}

sub pad_number {
  my ($width, $n) = @_;

  sprintf "%0${width}d", $n;
}

sub do_tags {
  my (@tags) = @_;

  {
    local $, = ' ';
    say "searching for posts with tags @tags" if show_progress();
  };

  my $params = $http->www_form_urlencode({ tags => join '+', @tags });
  my $count = get_post_count($params);
  my $num_pages = ceil($count / $POSTS_PER_PAGE);

  for my $page (1..$num_pages) {
    my $params = $http->www_form_urlencode({
      tags => join('+', @tags),
      page => $page,
      limit => $POSTS_PER_PAGE,
    });
    my $url = build_url("/posts.json?$params");
    my $resp = $http->get($url);
    assert_request_success($resp);

    my $post_infos = decode_json($resp->{content});
    for my $info (@$post_infos) {
      try {
        say "downloading post $info->{id}" if show_progress();
        my $filename = "$info->{md5}.$info->{file_ext}";
        download_file($info->{file_url} => $filename);
      } catch {
        warn "error downloading post $info->{id}, $_";
      };
    }
  }
}

sub get_post_info {
  my ($id) = @_;

  say "getting post info for post $id" if show_debug();

  my $url = build_url("/posts/$id.json");
  my $resp = $http->get($url);
  assert_request_success($resp);

  return decode_json($resp->{content});
}

sub get_pool_info {
  my ($id) = @_;

  say "getting pool info for pool $id" if show_debug();

  my $url = build_url("/pools/$id.json");
  my $resp = $http->get($url);
  assert_request_success($resp);

  return decode_json($resp->{content});
}

sub get_post_count {
  my ($params) = @_;

  say "getting post count for query $params" if show_debug();

  my $url = build_url("/counts/posts.json?$params");
  my $resp = $http->get($url);
  assert_request_success($resp);

  return decode_json($resp->{content})->{counts}{posts};
}

sub download_file {
  my ($file_url, $filename) = @_;

  say "downloading $file_url => $filename..." if show_progress();

  my $resp = $http->mirror(build_url($file_url), $filename);
  assert_request_success($resp);

  say 'done!' if show_progress();
}

sub build_url {
  my ($endpoint) = @_;

  return defined $auth
    ? "$SCHEME://$auth\@$HOST$endpoint"
    : "$SCHEME://$HOST$endpoint";
}

sub assert_request_success {
  my ($resp) = @_;

  unless ($resp->{success}) {
    say encode_json($resp) if show_debug();
    confess "$resp->{status} $resp->{reason}";
  }
}

sub show_progress {
  $verbose >= $PROGRESS;
}

sub show_debug {
  $verbose >= $DEBUG;
}
