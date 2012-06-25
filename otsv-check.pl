#! /usr/bin/perl -w

# Trialtool: Verschiedene Konsistenzprüfungen für den ÖTSV

# Copyright (C) 2012  Andreas Gruenbacher  <andreas.gruenbacher@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more
# details.
#
# You can find a copy of the GNU Affero General Public License at
# <http://www.gnu.org/licenses/>.

use utf8;

use File::Glob ':glob';
use File::Temp qw(tempfile);
use Getopt::Long;
use Trialtool;
use Encode::Locale qw(decode_argv);
use Time::localtime;
use strict;

my $wertung = 0;  # Index von Wertung 1 (0 .. 3)
my $anzeigen_mit;

my $STDOUT_encoding = -t STDOUT ? "console_out" : "UTF-8";
my $STDERR_encoding = -t STDERR ? "console_out" : "UTF-8";
binmode STDIN, ":encoding(console_in)";
binmode(STDOUT, ":encoding($STDOUT_encoding)");
binmode(STDERR, ":encoding($STDERR_encoding)");

my $result = GetOptions("wertung=i" => sub { $wertung = $_[1] - 1; },
			"anzeigen-mit=s" => \$anzeigen_mit);

unless ($result && @ARGV) {
    print "VERWENDUNG: $0 [--wertung=(1..4)] {datei|verzeichnis} ...\n";
    exit 1;
}

sub lizenzfahrer($) {
    my ($fahrer) = @_;

    return $fahrer->{startnummer} < 100;
}

sub alter($) {
    my ($fahrer) = @_;

    return undef
	unless exists $fahrer->{geburtsdatum} &&
	       $fahrer->{geburtsdatum} =~ /^(\d{4})-(\d{1,2})-(\d{1,2})$/;

    return (localtime->year() + 1900) - $1 - 1;
}

my ($tempfh, $tempname);
if ($anzeigen_mit) {
    ($tempfh, $tempname) = tempfile("otsv-check-XXXXXX", SUFFIX => ".txt", UNLINK => 1)
	or die "$!\n";
    STDOUT->fdopen($tempfh, "w")
	or die "$tempname: $!\n";
    binmode STDOUT, ":pop:encoding(UTF-8)";
}

if ($^O =~ /win/i) {
    @ARGV = map { bsd_glob($_, GLOB_NOCASE) } @ARGV;
}

decode_argv;

foreach my $name (trialtool_dateien @ARGV) {
    my ($otsv, $osk);
    my $fehler;

    my $cfg = cfg_datei_parsen("$name.cfg");
    my $fahrer_nach_startnummer = dat_datei_parsen("$name.dat");

    my $gestartete_klassen = gestartete_klassen($cfg);
    map { $otsv = 1 if $_ } @$gestartete_klassen[0 .. 9];
    map { $osk = 1 if $_ } @$gestartete_klassen[10 .. 14];

    print "$name\n" . ("=" x length $name) . "\n\n";

    if ($osk) {
	print "Nachdem bei dieser Veranstaltung OSK-Klassen starten, treten " .
	      "OSK-Lizenzfahrer und ÖTSV-Fahrer getrennt an.\n";
    } else {
	print "Nachdem bei dieser Veranstaltung keine OSK-Klassen starten, " .
	      "treten OSK-Lizenzfahrer und ÖTSV-Fahrer in gemeinsamen " .
	      "Klassen an.\n";
    }
    print "\n";

    my $otsv_klassen = [1, 1, 1, 1, 1, 1, 1];
    my $osk_klassen = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1];
    my $startende_klassen;
    my $klassen_adw;  # Klassen, die außerhalb aller Wertungen fahren
    my $klassen_adjw;  # Klassen, die außerhalb der Jahreswertung fahren
    my $klassen_fuer_lizenzfahrer;
    if ($osk) {
	$startende_klassen = [0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1];
	$klassen_adw = [1];
	$klassen_adjw = [1, 0, 0, 0, 1];
	$klassen_fuer_lizenzfahrer = $osk_klassen;
    } else {
	$startende_klassen = $otsv_klassen;
	$klassen_adw = [];
	$klassen_adjw = [1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 1];
	$klassen_fuer_lizenzfahrer = $otsv_klassen;
    }
    my $alter_minmax = {
	 3 => [ undef, 44 ],
	11 => [ 14 ],
	12 => [ 12, 18 ],
	13 => [ 10, 16 ],
    };

    for (my $n = 0; $n < @$gestartete_klassen || $n < @$startende_klassen; $n++) {
	if (!$gestartete_klassen->[$n] != !$startende_klassen->[$n]) {
	    print "Fehler: Es sind " .
		  ($gestartete_klassen->[$n] ? "" : "keine ") .
		  "Sektionen für Klasse " . ($n + 1) .
		  " selektiert, Klasse " . ($n + 1) . " " .
		  ($gestartete_klassen->[$n] ?
		   "darf bei dieser Veranstaltung aber nicht" :
		   "muss bei dieser Veranstaltung aber") .
		  " starten.\n";
	    $fehler++;
	}
    }
    if ($fehler) {
	print "=> Bitte korrigieren Sie die Sektionsauswahl in den " .
	      "Veranstaltungs-Einstellungen.\n\n";
	$fehler = 0;
    }

    # Hat ein Fahrer mehrere Startnummern in der selben Klasse?
    my $fahrer_nach_name;
    foreach my $startnummer (keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	my $name = "$fahrer->{nachname}, $fahrer->{vorname}";
	my $klasse = $fahrer->{klasse};
	push @{$fahrer_nach_name->{$name}{$klasse}}, $startnummer;
    }
    foreach my $klassen (values %$fahrer_nach_name) {
	foreach my $startnummern (values %$klassen) {
	    next
		unless @$startnummern > 1;
	    my $fahrer = $fahrer_nach_startnummer->{$startnummern->[0]};
	    print "Fehler: Fahrer $fahrer->{nachname} $fahrer->{vorname} " .
		  "hat mehrere Startnummern in Klasse $fahrer->{klasse}: " .
		  join(", ", sort { $a <=> $b } @$startnummern) . ".\n";
	   $fehler++;
	}
    }
    if ($fehler) {
	print "=> Bitte geben Sie den Fahrern ihre ursprünglichen Startnummern " .
	      "und löschen Sie die neuen Startnummern. Falls es sich nicht um " .
	      "mehrere Personen handelt, stellen Sie bitte sicher, dass der " .
	      "Name eindeutig ist.\n\n";
	$fehler = 0;
    }

    # Sind bei Fahrern Ergebnisse eingetragen sind, obwohl die Papierabnahme
    # nicht erfolgt ist ist?
    foreach my $startnummer (keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if ($fahrer->{runden} != 0 && !$fahrer->{papierabnahme}) {
	    print "Warnung: Für Fahrer $startnummer $fahrer->{nachname} " .
		  "$fahrer->{vorname} sind Ergebnisse eingetragen, obwohl " .
		  "die Papierabnahme nicht eingetragen ist.\n";
	    $fehler = 1;
	}
    }
    if ($fehler) {
	print "=> Bitte überprüfen Sie ob die Papierabnahme erfolgt ist, " .
	      "und tragen die Papierabnahme ein.\n\n";
	$fehler = 0;
    }

    # Fahrer ohne Papierabnahme von weiteren Checks ausnehmen
    foreach my $startnummer (keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	unless ($fahrer->{papierabnahme}) {
	    delete $fahrer_nach_startnummer->{$startnummer};
	}
    }

    # Lizenzfahrer ohne eingetragener Lizenznummer?
    foreach my $startnummer (keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if (lizenzfahrer($fahrer) &&
	    $fahrer->{lizenznummer} eq "") {
	    print "Warnung: Fahrer $startnummer $fahrer->{nachname} " .
		  "$fahrer->{vorname} hat eine Startnummer aus einer " .
		  "OSK-Lizenz-Klasse, es ist aber keine Lizenznummer " .
		  "eingetragen.\n";
	    $fehler++;
	}
    }
    if ($fehler) {
	print "=> Bitte tragen Sie die Lizenznummern dieser Fahrer nach.\n\n";
	$fehler = 0;
    }

    # Startet ein OSK-Lizenzfahrer in der falschen Klasse?
    foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if (lizenzfahrer($fahrer) &&
	    !$klassen_fuer_lizenzfahrer->[$fahrer->{klasse} - 1]) {
	    print "Fehler: OSK-Lizenzfahrer $startnummer " .
		  "$fahrer->{nachname} $fahrer->{vorname} ist in Klasse " .
		  "$fahrer->{klasse}, darf aber nur " .
		  ($osk ? "in seiner OSK-Klasse" :
		   ("um die Tageswertung in der entsprechenden ÖTSV-Klasse oder " .
		    "aus der Wertung in einer anderen ÖTSV-Klasse")) .
		   " antreten.\n";
	    $fehler = 1;
	}
    }
    # Hat ein Fahrer eine Klasse, die nicht startet?
    foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if (!lizenzfahrer($fahrer) &&
	    !$startende_klassen->[$fahrer->{klasse} - 1]) {
	    print "Fehler: Fahrer $startnummer " .
		  "$fahrer->{nachname} $fahrer->{vorname} ist in Klasse " .
		  "$fahrer->{klasse}, diese Klasse startet aber " .
		  "nicht.\n";
	    $fehler++;
	}
    }
    # Startet ein "normaler" Fahrer in einer Lizenzklasse?
    foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if (!lizenzfahrer($fahrer) &&
	    $startende_klassen->[$fahrer->{klasse} - 1] &&
	    $osk_klassen->[$fahrer->{klasse} - 1] &&
	    $fahrer->{ausfall} != 4) {  # 4 == aus der wertung
	    print "Fehler: Fahrer $startnummer " .
		  "$fahrer->{nachname} $fahrer->{vorname} ist kein " .
		  "Lizenzfahrer, und darf in OSK-Klasse $fahrer->{klasse} " .
		  "nicht starten.\n";
	    $fehler++;
	}
    }
    if ($fehler) {
	print "=> Bitte korrigieren Sie die Klassen dieser Fahrer.\n\n";
	$fehler = 0;
    }

    # "Jahreswertung" selektiert, obwohl Fahrer nicht gewertet werden darf?
    foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if ($fahrer->{wertungen}[$wertung] &&
	    $klassen_adjw->[$fahrer->{klasse} - 1] &&
	    $fahrer->{ausfall} != 4) {  # 4 == aus der wertung
	    print "Fehler: Fahrer $startnummer " .
		  "$fahrer->{nachname} $fahrer->{vorname} in Klasse " .
		  "$fahrer->{klasse} ist in der " .
		  "$cfg->{wertungen}[$wertung], diese Klasse nimmt aber " .
		  "nicht an der Wertung teil.\n";
	    $fehler++;
	}
    }
    if ($fehler) {
	print "=> Bitte deaktivieren Sie das $cfg->{wertungen}[$wertung]-" .
	      "Häkchen oder korrigieren Sie die Klassen dieser Fahrer.\n\n";
	$fehler = 0;
    }

    if (!$osk) {
	foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	    my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	    if (lizenzfahrer($fahrer) &&
		$fahrer->{wertungen}[$wertung] &&
		$fahrer->{ausfall} != 4) {  # 4 = aus der wertung
		print "Fehler: Lizenzfahrer $startnummer " .
		      "$fahrer->{nachname} $fahrer->{vorname} in Klasse " .
		      "$fahrer->{klasse} ist in der " .
		      "$cfg->{wertungen}[$wertung], darf aber nicht an " .
		      "dieser Wertung teilnehmen.\n";
		$fehler++;
	    }
	}
	if ($fehler) {
	    print "=> Bitte deaktivieren Sie das $cfg->{wertungen}[$wertung]-" .
		  "Häkchen dieser Fahrer.\n\n";
	    $fehler = 0;
	}
    }

    foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if ((!lizenzfahrer($fahrer) || $osk) &&
	    !$fahrer->{wertungen}[$wertung] &&
	    !$klassen_adjw->[$fahrer->{klasse} - 1] &&
	    $fahrer->{ausfall} != 4) {  # 4 == aus der wertung
	    my $zusatzinfo = "";
	    if ($fahrer->{klasse} == 11 || $fahrer->{klasse} == 12 ||
		$fahrer->{klasse} == 13) {
		$zusatzinfo = " (Bei ausländischen Lizenzfahrern ist das korrekt.)";
	    }
	    print "Warnung: Fahrer $startnummer " .
		  "$fahrer->{nachname} $fahrer->{vorname} in Klasse " .
		  "$fahrer->{klasse} ist nicht in der " .
		  "$cfg->{wertungen}[$wertung], diese Klasse nimmt aber " .
		  "an der Wertung teil.$zusatzinfo\n";
	    $fehler++;
	}
    }
    if ($fehler) {
	print "=> Bitte aktivieren Sie das $cfg->{wertungen}[$wertung]-" .
	      "Häkchen oder korrigieren Sie die Klasse dieser Fahrer.\n\n";
	$fehler = 0;
    }

    foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	my $klasse = $fahrer->{klasse};

	my $alter = alter($fahrer);
	unless ($alter) {
	    print "Warnung: Geburtsdatum von Fahrer $startnummer " .
		  "$fahrer->{nachname} $fahrer->{vorname} " .
		  "fehlt.\n";
	    $fehler++;
	    next;
	}
	next unless exists $alter_minmax->{$klasse};
	my ($min, $max) = @{$alter_minmax->{$klasse}};
	if ((defined $min && $alter < $min) ||
	    (defined $max && $alter > $max)) {
	    print "Fehler: Fahrer $startnummer " .
		  "$fahrer->{nachname} $fahrer->{vorname} " .
		  "war $alter Jahre alt, und darf daher " .
		  "nicht in Klasse $klasse starten.\n";
	    $fehler++;
	}
    }
    if ($fehler) {
	print "=> Bitte korrigieren Sie die Geburtsdaten oder Klassen " .
	      "dieser Fahrer.\n\n";
	$fehler = 0;
    }

    # Fahrer, die noch unterwegs sind
    print "Fahrer auf der Strecke:\n";
    foreach my $startnummer (sort { $a <=> $b } keys %$fahrer_nach_startnummer) {
	my $fahrer = $fahrer_nach_startnummer->{$startnummer};
	if ($fahrer->{runden} != $cfg->{runden}[$fahrer->{klasse} - 1] &&
	    ($fahrer->{ausfall} == 0 || $fahrer->{ausfall} == 4)) {
	    printf "  %3u %s %s (Runde %s)\n", $startnummer, $fahrer->{nachname},
				    $fahrer->{vorname}, $fahrer->{runden} + 1;
	    $fehler++;
	}
    }
    if ($fehler) {
	print "\n";
	$fehler = 0;
    } else {
	print "  Keine\n\n";
    }
}
print "Check beendet.\n";

if ($anzeigen_mit) {
    system $anzeigen_mit, $tempname;
    # Windows won't allow to unlink an open file ...
    close STDOUT;
}
