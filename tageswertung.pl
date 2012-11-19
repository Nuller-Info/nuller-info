#! /usr/bin/perl -w

# Trialtool: Auswertung einer Veranstaltung machen ("Tageswertung")

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

# TODO:
# * Ergebnisse in Editor-Programm darstellen (notepad?)

use open IO => ":locale";
use utf8;

use File::Glob ':glob';
use Getopt::Long;
use Trialtool;
use RenderOutput;
use Wertungen;
use strict;

my $shtml = "html/tageswertung.shtml";
my $wertung = 0;  # Index von Wertung 1 (0 .. 3)
my $spalten;

my $result = GetOptions("wertung=i" => sub { $wertung = $_[1] - 1; },
			"html" => \$RenderOutput::html,

			"club" => sub { push @$spalten, $_[0] },
			"fahrzeug" => sub { push @$spalten, $_[0] },
			"geburtsdatum" => sub { push @$spalten, $_[0] },
			"lizenznummer" => sub { push @$spalten, $_[0] });
unless ($result) {
    print "VERWENDUNG: $0 [--wertung=(1..4)] [--html] [--club] [--lizenznummer] [--fahrzeug] [--geburtsdatum]\n";
    exit 1;
}

my %FH;
if ($RenderOutput::html) {
    open FH, $shtml
	or die "$shtml: $!\n";
    while (<FH>) {
	last if (/<!--#include.*?-->/);
	s/<!--.*?-->//g;
	print;
    }
}

if ($^O =~ /win/i) {
    @ARGV = map { bsd_glob($_, GLOB_NOCASE) } @ARGV;
}

foreach my $name (trialtool_dateien @ARGV) {
    my $cfg = cfg_datei_parsen("$name.cfg");
    my $fahrer_nach_startnummer = dat_datei_parsen("$name.dat");
    rang_und_wertungspunkte_berechnen $fahrer_nach_startnummer, $cfg;

    doc_h1 "Tageswertung mit Punkten für die $cfg->{wertungen}[$wertung]";
    doc_h2 doc_text "$cfg->{titel}[$wertung]\n$cfg->{subtitel}[$wertung]";
    tageswertung $cfg, $fahrer_nach_startnummer, $wertung, $spalten;
}

if ($RenderOutput::html) {
    while (<FH>) {
	s/<!--.*?-->//g;
	print;
    }
}
