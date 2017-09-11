#!/usr/bin/perl

$locale = "";

for ($i=0; $i<=$#ARGV; $i++) {
	if ($ARGV[$i] =~ /^\-/) {
		last;
	}
	usage() if ($ARGV[$i] eq "");
	if ($locale eq "") {
		$locale = $ARGV[$i];
		usage() if ($locale !~ /^\w+$/);
		next;
	}
	usage();
}

$javadoc_args = " --";
for (; $i<=$#ARGV; $i++) {
	if ($ARGV[$i] =~ /\s/) {
		$javadoc_args .= " \"" . $ARGV[$i] . "\"";
	} else {
		$javadoc_args .= " " . $ARGV[$i];
	}
}

$folder = $locale eq "" ? "default" : $locale;

$locale = " -locale $locale" if ($locale ne "");

$cmd = "perl javadoc_wrapper.pl$locale jdoc.lst$javadoc_args -noqualifier \"java.*\" -protected -nodeprecated -encoding utf8 -charset utf8 -d Document/jdoc/$folder";
system($cmd);

sub usage
{
	die "Usage: jdoc.pl [locale] [javadoc_options]\n";
}
