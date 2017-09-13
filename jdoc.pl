#!/usr/bin/perl

@locales = ();

for ($i=0; $i<=$#ARGV; $i++) {
	if ($ARGV[$i] =~ /^\-/) {
		last;
	}
	usage() if ($ARGV[$i] !~ /^\w+$/);
	push @locales, $ARGV[$i];
}

$locale_set = 0;
for (; $i<=$#ARGV; $i++) {
	if ($ARGV[$i] =~ /\s/) {
		$javadoc_args .= " \"" . $ARGV[$i] . "\"";
	} else {
		$javadoc_args .= " " . $ARGV[$i];
	}
	$locale_set = 1 if ($ARGV[$i] eq "-locale");
}

push @locales, "default" if ($#locales < 0);


foreach $lcl (@locales) {
	$cmd = "perl javadoc_wrapper.pl -locale $lcl jdoc.lst --";
	$cmd .= " -locale " . trans_locale($lcl) if (!$locale_set);
	$cmd .= $javadoc_args;
	$cmd .= " -noqualifier \"java.*\" -protected -nodeprecated -encoding utf8 -charset utf8 -d Document/jdoc/$lcl";
	print $cmd, "\n";
	system($cmd);
}

sub usage
{
	die "Usage: jdoc.pl [locale1[, locale2, ...]] [javadoc_options]\n";
}

sub trans_locale
{
	my $locale = shift;
	return "en_US" if ($locale eq "default");
	return "en_US" if ($locale =~ /^en(_\w+)?$/);
	return $locale;
}

