#!/usr/bin/perl

use Cwd qw(getcwd abs_path);
use File::Path qw(make_path remove_tree);
use File::Copy;

$opt_doc_locale = "default";
$list_file = "";

# parse command line

for ($i=0; $i<=$#ARGV; $i++) {
	# end of wrapper options
	if ($ARGV[$i] eq "--") {
		usage() if ($list_file eq "");
		$i++;
		last;
	}
	# locale of document
	if ($ARGV[$i] eq "-locale") {
		usage() if ($i == $#ARGV);
		$opt_doc_locale = lc($ARGV[++$i]);
		usage() if ($opt_doc_locale !~ /^\w+$/);
		next;
	}
	# list file (java file list)
	if ($ARGV[$i] !~ /^\-/ && $ARGV[$i] ne "" && $list_file eq "") {
		$list_file = $ARGV[$i];
		next;
	}
	# unknown options
	usage();
}

# collect options to be passed to javadoc

$javadoc_args = "";
for (; $i<=$#ARGV; $i++) {
	$arg = $ARGV[$i];
	if ($arg =~ /\s/) {
		$arg = "\"$arg\"";	# TODO: argument with quotation marks
	}
	$javadoc_args .= " $arg";
}

# preprocess files and save in temporary directory

$list_file = "jdoc.lst" if ($list_file eq "");
@lines = load_file_lines($list_file);
exit(1) if ($#lines < 0);

$tmp_dir = create_tmp_dir();

@srcs = ();
foreach $f (@lines) {
	if ($f =~ /^\s*(.+\.java)\s*$/) {
		$f = get_slash_path($1);
		if (!-f $f) {
			warn("$f not found!\n");
			next;
		}
		$f = abs_path($f);
		$d = get_copy_path($f, $tmp_dir);
		parse_java_file($f, $d);
		push @srcs, $d;
	}
}

if ($#srcs < 0) {
	remove_tree($tmp_dir);
	die "No files found!\n";
}

# run javadoc

save_file_lines("$tmp_dir.lst", \@srcs, "\n");
system("javadoc$javadoc_args \@$tmp_dir.lst");
unlink("$tmp_dir.lst");

# delete temporary directory

remove_tree($tmp_dir);

exit(0);

sub usage
{
	die "Usage: javadoc_wrapper.pl [-locale <locale>] <list_file> [-- [javadoc options]]\n";
}

sub init_context
{
	$doc_locale = shift;			# required locale of document generated by javadoc
	$doc_in_comment = 0;			# in javadoc comment
	$doc_out_ok = 1;				# comment locale matches $doc_locale
	%doc_macros = ();				# macros
	%doc_ints = ();					# auto-increasing integers
	@doc_cmt_locale_list = ();		# current comment locale(s)
	$doc_error = 0;					# error state
	@doc_repeat_lines = ();			# buffered lines for multi-round expanding
	$doc_repeat_collected = 0;		# whether all multi-round lines are collected
	$doc_repeat = 0;				# repeat
}

sub parse_java_file
{
	my $src = shift;
	my $dst = shift;

	my $dir = substr($dst, 0, rindex($dst, '/'));
	make_path($dir);
	
	my $fd_in, $fd_out;

	if (!open $fd_in, "<", $src) {
		warn("Cannot open $src!\n");
		return;
	}
	if (!open $fd_out, ">", $dst) {
		warn("Cannot create $dst!\n");
		close $fd_in;
		return;
	}

	init_context($opt_doc_locale);

	while (<$fd_in>) {
		s/(\r|\n)//g;
		my $text = parse_java_line($_);
		if ($doc_repeat > 1) {
			push @doc_repeat_lines, $text if ($text ne "");
			if ($doc_repeat_collected) {
				while ($doc_repeat-- > 1) {
					my @new_lines = ();
					foreach $text (@doc_repeat_lines) {
						$text = parse_java_line($text);
						push @new_lines, $text if ($text ne "");
					}
					@doc_repeat_lines = @new_lines;
					undef @new_lines;
				}
				foreach $text (@doc_repeat_lines) {
					print $fd_out $text, "\n" if ($text ne "");
				}
				$doc_repeat_lines = ();
				$doc_repeat_collected = 0;
				$doc_repeat = 0;
			}
		} else {
			print $fd_out $text, "\n" if ($text ne "");
		}
	}

	close $fd_out;
	close $fd_in;
}

sub parse_java_line
{
	my $text = shift;

	my $result = "";

	if (!$doc_in_comment) {												# not inside comment block
		$result = $text;												# output if not inside javadoc comment block
		if ($text =~ /^\s*\/\*\*/) {									# beginning of javadoc comment, a line beginning with /**
			$doc_in_comment = 1;										# 		inside comment block now
			@doc_cmt_locale_list = ();									#		clear comment locales
			$doc_out_ok = 1;											# 		OK to output
		}
	} elsif ($text =~ /^\s*\*+\//) {									# end of javadoc comment
		$result = $text;												# output the line
		$doc_in_comment = 0;											# outside comment block now
	} elsif ($text =~ /^[\s\*]*\@locale\s+(\w+)\s*=\s*(\w+)\s*$/) {		# locale redirection
		$doc_locale = lc($2) if ($doc_locale eq lc($1));				#		change $doc_locale
	} elsif ($text =~ /^[\s\*]*\@locale(\s+\w+(\s*,\s*\w+)*)?\s*$/) {	# setting current comment locales
		@doc_cmt_locale_list = split_locale_list($1, 0);				#		the list
		$doc_out_ok = match_doc_locale(\@doc_cmt_locale_list);			#		match
	} elsif ($text =~ /^[\s\*]*\@macro\s+(\w+)(.*)/) {					# macro
		parse_macro($1, $2);											#		parse
	} elsif ($text =~ /^[\s\*]*\@repeat\s+(\w+)\s*$/) {					# begin repeat
		if ($1 > 1 && $doc_repeat == 0) {
			@doc_repeat_lines = ();
			$doc_repeat_collected= 0;
			$doc_repeat = $1;
		}
	} elsif ($text =~ /^[\s\*]*\@repeat\s*$/) {							# end repeat
		if ($doc_repeat > 1) {
			$doc_repeat_collected = 1;
		}
	} elsif ($text =~ /^[\s\*]*\@int\s+(\w+)(.*)/) {					# auto-increasing integer
		parse_int($1, $2);												#		parse
	} elsif ($text =~ /^[\s\*]*\@(locale|macro|int|repeat)(\W*)?/) {	# ignore unmatched tag lines
		#print "IGNORED: $text\n";
	} else {
		$result = expand_line($text) if ($doc_out_ok);					# expand line
	}

	return $result;
}

sub split_locale_list
{
	my $locales = shift;
	my $set_default = shift;
	$locales = "default" if ($locales eq "" && $set_default);
	return split_list(lc($locales));
}

sub split_list
{
	my $text = shift;
	$text =~ s/\s//g;
	return split(/,/, $text);
}

sub match_doc_locale
{
	my $text_locale_list = shift;			# current comment locales

	return 1 if ($#$text_locale_list < 0);	# no locales specified, OK to output
	foreach my $lcl (@$text_locale_list) {
		return 1 if ($lcl eq $doc_locale);	# one of the locales matched, OK to output
	}
	return 0;
}

sub parse_macro
{
	my $word = shift;
	my $text = shift;

	if ($text =~ /^\s*\((.*)/) {			# require left parenthesis
		$text = $1;
		# locale list, colon, and meaning
		my @locales = ();					# array of locale lists
		my @meanings = ();					# array of meanings
		my $delim = "";						# delimiter: , or )
		while ($text =~ /^\s*(\w+(\s*,\s*\w+)*)?\s*:((\$.|[^,\)])*)([,\)])(.*)/) {
			my $l = $1;						# locale
			my $m = $3;						# meaning
			$delim = $5;					# , or )
			$text = $6;						# following text
			push @locales, $l;				# locale list
			push @meanings, unescape_dollar_sequence($m);
			last if ($delim eq "\)");
		}
		$text = $delim . $text;
		if ($text =~ /^\s*\)\s*$/) {		# must end with right parenthesis
			add_macro($word, \@meanings, \@locales) if ($#meanings >= 0);
		}
	}
}

sub unescape_dollar_sequence
{
	my $text = shift;
	my $result = "";

	# scan from the beginning. 's///' is not for the case.
	while ($text =~ /^(.*?)\$(.)?(.*)/) {	# non-greedy!!
		$result .= $1 . get_escaped_char($2);	# '$' followed by no characters will be removed
		$text = $3;
	}
	$result .= $text;						

	return $result;
}

sub get_escaped_char
{
	my $c = shift;
	
	return "\n" if ($c eq "n");
	
	return $c;
}

sub add_macro
{
	my $word = shift;
	my $meanings = shift;		# array reference
	my $locales = shift;		# array reference

	my %ms = ();

	for (my $i=0; $i<=$#$meanings; $i++) {
		my @ls = split_locale_list($$locales[$i], 1);
		foreach my $t (@ls) {
			$ms{$t} = $$meanings[$i];
		}
	}
	$doc_macros{$word} = \%ms;	# hash reference
}

sub dump_macros
{
	while (my ($word, $meanings) = each (%doc_macros)) {
		print "$word: {\n";
		while (my ($l, $m) = each (%$meanings)) {
			print "\t$l: $m\n";
		}
		print "}\n";
	}
}

sub lookup_macro
{
	my $word = shift;
	my $rst = shift;

	my $meaning = "";

	if ($word ne "") {
		my $ms = $doc_macros{$word};
		if (defined $ms) {
			if ($#doc_cmt_locale_list < 0) {					# if no comment locales are set, assume $doc_locale
				$meaning = $$ms{$doc_locale};
			} else {
				foreach my $l (@doc_cmt_locale_list) {			# one of comment locales matches
					$meaning = $$ms{$l};
					last if (defined $meaning);
				}
			}
			$meaning = $$ms{'default'} if (!defined $meaning);	# no locale matched, search for 'all'
			$meaning = "" if (!defined $meaning);
		} else {
			$ms = $doc_ints{$word};
			if (defined $ms) {
				$$ms[2] = $$ms[0] if ($rst);
				$meaning = $$ms[2];
				$$ms[2] += $$ms[1];
			}
		}
	}

	return $meaning;
}

sub parse_int
{
	my $word = shift;
	my $text = shift;

	if ($text =~ /^\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)/) {
		my @vs = ($1, $2, $1);
		$doc_ints{$word} = \@vs;
	}
}

sub expand_line
{
	my $text = shift;

	my $org_text = $text;
	my $result = "";
	my $sub_result = "";

	$doc_error = 0;												# reset error state
	while ($doc_error == 0 && $text =~ /^(.*?)\$(.)?(.*)/) {	# non-greedy
		$result .= $1;
		if ($2 eq "{") {
			($sub_result, $text) = expand_macro($3);			# found macro
			$result .= $sub_result;
		} else {
			$result .= get_escaped_char($2);					# '$' followed by no characters will be removed
			$text = $3;
		}
	} 
	$result .= $text;
	return $doc_error == 0 ? $result : $org_text;
}

sub expand_macro
{
	my $text = shift;

	my $word;
	my $repeat;
	my $repeat_count;
	my $back_ref;
	my $s;
	my @list;

	my $result = "";

	while ($doc_error == 0 && $text ne "") {

		# not closed
		if ($text =~ /^\s*$/) {
			$doc_error = 1;
			last;
		}

		# closed
		if ($text =~ /^(\s*)\}(.*)/) {
			$text = $2;
			$result = $1 if ($result eq "");		#		pure white spaces
			last;
		}

		# inline locales
		if ($text =~ /^\s*(\w+(\s*,\s*\w+)*)?\s*:(.*)/) {
			$text = $3;
			@list = split_locale_list($1, 1);
			($s, $text) = expand_macro_text($text);
			if (match_doc_locale(\@list)) {
				$result .= $s;
			}
			next;
		}

		# simple macros
		if ($text =~ /^\s*(\w+(\s*\*\s*\d*)?(\s*=\s*\w+)?(\s*,\s*\w+(\s*\*\s*\d*)?(\s*=\s*\w+)?)*)\s*\}(.*)/) {
			$text = $7;
			@list = split_list($1);
			foreach $s (@list) {
				$s =~ /^(\w+)(\*(\d*))?(=(\w+))?/;
				$word = $1;
				$repeat = $2;
				$repeat_count = $3;
				$back_ref = $5;
				$s = dup_string(lookup_macro($word, $repeat eq "*" ? 1 : 0), $repeat_count eq "" ? 1 : $repeat_count);
				$doc_macros{$back_ref} = { 'default' => $s } if ($back_ref ne "");
				$result .= $s;
			}
			last;
		}

		# macro with parameters
		if ($text =~ /^\s*(\w+)(\s*\*\s*(\d+))?(\s*=\s*(\w+))?\s*#(.*)/) {
			$text = $6;
			$word = $1;
			$repeat = $2;
			$repeat_count = $3;
			$back_ref = $5;
			@list = ();
			$text = expand_macro_arg_list($text, \@list);
			$s = dup_string(subst_args(lookup_macro($word, 0), \@list), $repeat_count eq "" ? 1 : $repeat_count);
			$doc_macros{$back_ref} = { 'default' => $s } if ($back_ref ne "");
			$result .= $s;
			next;
		}

		# unexpected
		$doc_error = 3;
	}

	return ($result, $text);
}

sub dup_string
{
	my $text = shift;
	my $copies = shift;
	my $s = "";
	while ($copies-- > 0) {
		$s .= $text;
	}
	return $s;
}

sub subst_args
{
	my $text = shift;
	my $args = shift;

	my $n = $#$args;

	my $i;
	my $result = "";

	while ($text =~ /^(.*?)\#(.)?(.*)/s) {
		$result .= $1;
		$i = $2;
		$text = $3;
		if ($i !~ /^\d$/) {
			$result .= $i;
		} else {
			$i--;
			$result .= $$args[$i] if ($i >= 0 && $i <= $n);
		}
	}
	$result .= $text;

	return $result;
}

sub expand_macro_arg_list
{
	my $text = shift;
	my $args = shift;

	my $s, $t;

	while (1) {
		($s, $text) = expand_macro_arg($text);
		if ($text eq "") {
			$doc_error = 2;
			last;
		}
		$t = substr($text, 0, 1);
		$text = substr($text, 1) if ($t eq ",");
		if ($t eq ",") {
			push @$args, $s;
			next;
		}
		if ($t eq "}") {
			push @$args, $s if ($#$args >= 0 || $s ne "");
			last;
		}
		push @$args, $s if ($s ne "");
	}

	return $text;
}

sub expand_macro_arg
{
	my $text = shift;

	my $result = "";
	my $sub_result = "";

	$text =~ s/^\s*//;
	while ($doc_error == 0 && $text =~ /^(.*?)(\}|,|\$(.))(.*)/) {
		if ($2 eq "," || $2 eq "}") {
			$text = $2 . $4;			# keep '}' and ',' for caller
			if ($result ne "") {
				$result .= rtrim($1);
			} else {
				$result .= ltrim(rtrim($1));
			}
			return ($result, $text);
		} else {
			$result .= $1;
			if ($3 ne "{") {
				$result .= get_escaped_char($3);
				$text = $4;
			} else {
				($sub_result, $text) = expand_macro($4);
				$result .= $sub_result;
			}
		}
	}
	$result .= $text;

	return ($result, "");
}

sub ltrim
{
	my $text = shift;
	$text =~ s/^\s*(.*)/\1/;
	return $text;
}

sub rtrim
{
	my $text = shift;
	$text =~ s/^(.*?)\s*$/\1/;
	return $text;
}

sub expand_macro_text
{
	my $text = shift;

	my $result = "";
	my $sub_result = "";

	while ($doc_error == 0 && $text =~ /^(.*?)(\$(.)|\})(.*)/) {
		$result .= $1;
		if ($2 eq "}") {
			$text = $2 . $4;			# keep '}' for caller
			return ($result, $text);
		}
		if ($3 ne "{") {
			$result .= get_escaped_char($3);
			$text = $4;
		} else {
			($sub_result, $text) = expand_macro($4);
			$result .= $sub_result;
		}
	}
	$result .= $text;

	return ($result, "");
}

sub create_tmp_dir
{
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	my $dir = sprintf("doc-tmp-dir-%04d%02d%02d-%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
	die "Cannot create temporary directory!\n" if (!mkdir($dir));
	return $dir;
}

sub get_copy_path
{
	my $path = shift;
	my $tmpd = shift;
	if ($^O eq "MSWin32") {
		$path = substr($path, 0, 1) . substr($path, 2);
	} else {
		$path = substr($path, 1);
	}
	return "$tmpd/$path";
}

sub load_file_lines
{
	my $file = get_slash_path(shift);
	my @lines = ();
	my $fd;
	if (!open($fd, "<", $file)) {
		warn "Cannot open $file!\n";
		return;
	}
	while (<$fd>) {
		push @lines, $_;
	}
	close($fd);
	return @lines;
}

sub get_formal_path
{
	my $path = shift;
	if ($^O eq "MSWin32") {
		$path =~ s/\//\\/g;
		$path =~ s/\\\\/\\/g;
	} else {
		$path =~ s/\\/\//g;
		$path =~ s/\/\//\//g;
	}
	return $path;
}

sub get_slash_path
{
	my $path = shift;
	$path =~ s/\\/\//g;
	$path =~ s/\/\//\//g;
	return $path;
}

sub save_file_text
{
	my $file = shift;
	my $text = shift;
	open my $fd, ">", $file || die "Cannot create $file!\n";
	print $fd $text;
	close $fd;
}

sub save_file_lines
{
	my $file = shift;
	my $lines = shift;
	my $eol = shift;
	open my $fd, ">", $file || die "Cannot create $file!\n";
	foreach my $ln (@$lines) {
		print $fd $ln;
		print $fd $eol;
	}
	close $fd;
}
