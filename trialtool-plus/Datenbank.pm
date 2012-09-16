# Trialtool: Datenbankfunktionen

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

package Datenbank;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(cfg_aus_datenbank fahrer_aus_datenbank db_utf8);

sub cfg_aus_datenbank($$) {
    my ($dbh, $id) = @_;
    my $cfg;

    my $sth = $dbh->prepare(q{
	SELECT vierpunktewertung, wertungsmodus, punkte_sektion_auslassen,
	       wertungen_234_punkte, rand_links, rand_oben,
	       wertungspunkte_markiert, versicherung, ergebnislistenbreite,
	       ergebnisliste_feld
	FROM veranstaltung
	WHERE id = ?
    });
    $sth->execute($id);
    unless ($cfg = $sth->fetchrow_hashref) {
	return undef;
    }

    $sth = $dbh->prepare(q{
	SELECT wertung, titel, subtitel, bezeichnung
	FROM wertung
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	my $n = $row[0] - 1;
	$cfg->{titel}[$n] = $row[1];
	$cfg->{subtitel}[$n] = $row[2];
	$cfg->{wertungen}[$n] = $row[3];
    }

    $sth = $dbh->prepare(q{
	SELECT klasse, bezeichnung, fahrzeit, runden
	FROM klasse
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	my $n = $row[0] - 1;
	$cfg->{klassen}[$n] = $row[1];
	$cfg->{fahrzeiten}[$n] = $row[2];
	$cfg->{runden}[$n] = $row[3];
    }

    $cfg->{sektionen} = [];
    for (my $n = 0; $n < 15; $n++) {
	push @{$cfg->{sektionen}}, 'N' x 15;
    }
    $sth = $dbh->prepare(q{
	SELECT klasse, sektion
	FROM sektion
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	substr($cfg->{sektionen}[$row[0] - 1], $row[1] - 1, 1) = 'J';
    }

    $sth = $dbh->prepare(q{
	SELECT runde, farbe
	FROM kartenfarbe
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	$cfg->{kartenfarben}[$row[0] - 1] = $row[1];
    }

    $sth = $dbh->prepare(q{
	SELECT rang, punkte
	FROM wertungspunkte
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	$cfg->{wertungspunkte}[$row[0] - 1] = $row[1];
    }

    $sth = $dbh->prepare(q{
	SELECT feld
	FROM nennungsmaske_feld
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	$cfg->{nennungsmaske_felder}[$row[0] - 1] = 1;
    }
    return $cfg;
}

sub fahrer_aus_datenbank($$) {
    my ($dbh, $id) = @_;
    my $fahrer_nach_startnummer;

    my $sth = $dbh->prepare(q{
	SELECT startnummer, klasse, helfer, nenngeld, bewerber, nachname,
	       vorname, strasse, wohnort, plz, club, fahrzeug, geburtsdatum,
	       telefon, lizenznummer, rahmennummer, kennzeichen, hubraum,
	       bemerkung, land, helfer_nummer, startzeit, zielzeit, stechen,
	       papierabnahme, versicherung, runden, zusatzpunkte, punkte,
	       ausfall, nennungseingang
	FROM fahrer
	WHERE id = ?
    });
    $sth->execute($id);
    while (my $fahrer = $sth->fetchrow_hashref) {
	my $startnummer = $fahrer->{startnummer};
	$fahrer_nach_startnummer->{$startnummer} = $fahrer;
    }

    $sth = $dbh->prepare(q{
	SELECT startnummer, runde, sektion, punkte
	FROM punkte
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	my $startnummer = $row[0];
	$fahrer_nach_startnummer->{$startnummer}{punkte_pro_sektion}
	    [$row[1] - 1][$row[2] - 1] = $row[3];
	$fahrer_nach_startnummer->{$startnummer}{punkte_pro_runde}
	    [$row[1] - 1] += $row[3];
	if ($row[3] < 5) {
	    $fahrer_nach_startnummer->{$startnummer}{r}
		[$row[1] - 1][$row[3]]++;
	    $fahrer_nach_startnummer->{$startnummer}{s}
		[$row[3]]++;
	}
    }

    $sth = $dbh->prepare(q{
	SELECT startnummer, wertung
	FROM fahrer_wertung
	WHERE id = ?
    });
    $sth->execute($id);
    while (my @row = $sth->fetchrow_array) {
	my $startnummer = $row[0];
	$fahrer_nach_startnummer->{$startnummer}{wertungen}
	    [$row[1] - 1] = 1;
    }
    return $fahrer_nach_startnummer;
}

sub db_utf8($) {
    my ($db) = @_;

    if ($db =~ /^(DBI:)?mysql:/) {
	return mysql_enable_utf8 => 1;
    } elsif ($db = ~ /^(DBI:)?SQLite:/) {
	return sqlite_unicode => 1;
    }
    return ();
}
