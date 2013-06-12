# Trialtool: Datenbankfunktionen

# Copyright (C) 2013  Andreas Gruenbacher  <andreas.gruenbacher@gmail.com>
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

package DatenbankAktualisieren;
use Trialtool qw(gestartete_klassen);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(fahrer_aktualisieren veranstaltung_aktualisieren);
use strict;

# datensatz_aktualisieren
#
# Abhängig von den alten und neuen Werten für die einzelnen Felder wird er alte
# Datensatz gelöscht, aktualisiert, oder ein neuer Datensatz eingefügt.
#
sub datensatz_aktualisieren($$$$$$$$$) {
    my ($callback, $tabelle, $version_ref, $changed, $keys, $nonkeys, $kval, $alt, $neu) = @_;
    my ($sql, $args, $davor);

    if (defined $alt) {
	if (defined $neu) {
	    my $modified_nonkeys = [];
	    my $modified_old;
	    my $modified_new;
	    for (my $n = 0; $n < @$nonkeys; $n++) {
		unless ($alt->[$n] ~~ $neu->[$n]) {
		    push @$modified_nonkeys, $nonkeys->[$n];
		    push @$modified_old, $alt->[$n];
		    push @$modified_new, $neu->[$n];
		}
	    }
	    $nonkeys = $modified_nonkeys;
	    $alt = $modified_old;
	    $neu = $modified_new;
	    if (($version_ref && $changed) || @$nonkeys) {
		for (my $n = 0; $n < @$nonkeys; $n++) {
		    push @$davor, [ $nonkeys->[$n], $alt->[$n] ];
		}
		if ($version_ref) {
		    $sql = "UPDATE $tabelle " .
			"SET " . join(", ", (
			    "version = CASE WHEN version = ? THEN version + 1 ELSE -1 END",
			    map { "$_ = ?" } @$nonkeys)) . " " .
			"WHERE " . join(" AND ", map { "$_ = ?" } @$keys);
		    $args = [$$version_ref, @$neu, @$kval];
		} else {
		    $sql = "UPDATE $tabelle " .
			"SET " . join(", ", map { "$_ = ?" } @$nonkeys) . " " .
			"WHERE " . join(" AND ", map { "$_ = ?" } @$keys);
		    $args = [@$neu, @$kval];
		}
	    }
	} else {
	    if ($version_ref) {
		push @$keys, 'version';
		push @$kval, $$version_ref;
	    }
	    $sql = "DELETE FROM $tabelle " .
		"WHERE " . join(" AND ", map { "$_ = ?" } @$keys);
	    $args = $kval;
	    # FIXME: Gibt es eine vernünftige Möglichkeit festzustellen, ob der
	    # Datensatz mit einer anderen Version existiert?
	}
    } elsif (defined $neu) {
	if ($version_ref) {
	    $nonkeys = [ @$nonkeys, 'version' ];
	    $neu = [ @$neu, 1 ];
	}
	$sql = "INSERT INTO $tabelle (" . join(", ", @$keys, @$nonkeys) . ") " .
	    "VALUES (" . join(", ", map { "?" } (@$keys, @$nonkeys)) . ")";
	$args = [@$kval, @$neu];
    }
    if (defined $sql) {
	my $affected_rows = &$callback($sql, $args, $davor);
	if ($affected_rows != 1) {
	    die "'$sql': $affected_rows statt 1 Datensatz betroffen" .
		($neu ? "" : "; Version vermutlich ungültig") . "\n";
	}
	$$version_ref = $neu ? $$version_ref + 1 : 0
	    if $version_ref;
	return 1;
    }
    return undef;
}

sub deletes_updates_inserts($$) {
    my ($alt, $neu) = @_;
    my ($deletes, $updates, $inserts) = ([], [], []);

    foreach my $key (keys %$alt) {
	if (exists $neu->{$key}) {
	    push @$updates, $key;
	} else {
	    push @$deletes, $key;
	}
    }
    foreach my $key (keys %$neu) {
	push @$inserts, $key
	    unless exists $alt->{$key};
    }
    return ([sort @$deletes], [sort @$updates], [sort @$inserts]);
}

sub hash_aktualisieren($$$$$$$) {
    my ($callback, $tabelle, $keys, $nonkeys, $const_keys, $alt, $neu) = @_;
    my $changed;

    my ($deletes, $updates, $inserts) = deletes_updates_inserts($alt, $neu);
    foreach my $hashkey (@$deletes) {
	datensatz_aktualisieren $callback, $tabelle,
		undef, undef,
		$keys, $nonkeys,
		[@$const_keys, split(/:/, $hashkey)],
		$alt->{$hashkey},
		undef
	    and $changed = 1;
    }
    foreach my $hashkey (@$updates) {
	datensatz_aktualisieren $callback, $tabelle,
		undef, undef,
		$keys, $nonkeys,
		[@$const_keys, split(/:/, $hashkey)],
		$alt->{$hashkey},
		$neu->{$hashkey}
	    and $changed = 1;
    }
    foreach my $hashkey (@$inserts) {
	datensatz_aktualisieren $callback, $tabelle,
		undef, undef,
		$keys, $nonkeys,
		[@$const_keys, split(/:/, $hashkey)],
		undef,
		$neu->{$hashkey}
	    and $changed = 1;
    }
    return $changed;
}

sub punkte_pro_sektion_hash($) {
    my ($fahrer) = @_;

    my $hash = {};
    if ($fahrer) {
	my $punkte_pro_sektion = $fahrer->{punkte_pro_sektion} // [];
	for (my $runde = 0; $runde < @$punkte_pro_sektion; $runde++) {
	    my $punkte_in_runde = $punkte_pro_sektion->[$runde];
	    if ($punkte_in_runde) {
		for (my $sektion = 0; $sektion < @$punkte_in_runde; $sektion++) {
		    my $punkte = $punkte_in_runde->[$sektion];
		    next unless defined $punkte;
		    $hash->{($runde + 1) . ':' . ($sektion + 1)} = [ $punkte ];
		}
	    }
	}
    }
    return $hash;
}

sub punkte_pro_runde_hash($) {
    my ($fahrer) = @_;

    my $hash = {};
    if ($fahrer) {
	my $punkte_pro_runde = $fahrer->{punkte_pro_runde} // [];
	for (my $runde = 0; $runde < @$punkte_pro_runde; $runde++) {
	    $hash->{$runde + 1} = [ $punkte_pro_runde->[$runde] ];
	}
    }
    return $hash;
}

sub fahrer_wertungen_hash($) {
    my ($fahrer) = @_;

    my $hash = {};
    if ($fahrer) {
	my $wertungen = $fahrer->{wertungen} // [];
	for (my $n = 0; $n < @$wertungen; $n++) {
	    next unless $wertungen->[$n];
	    $hash->{$n + 1} = [ $fahrer->{wertungsrang}[$n], $fahrer->{wertungspunkte}[$n] ];
	}
    }
    return $hash;
}

sub einen_fahrer_aktualisieren($$$$$) {
    my ($callback, $id, $alt, $neu, $versionierung) = @_;
    my $startnummer = $alt ? $alt->{startnummer} : $neu->{startnummer};
    my $changed;

    if (!$neu || exists $neu->{punkte_pro_sektion}) {
	hash_aktualisieren $callback, 'punkte',
		[qw(id startnummer runde sektion)], [qw(punkte)],
		[$id, $startnummer],
		punkte_pro_sektion_hash($alt),
		punkte_pro_sektion_hash($neu)
	    and $changed = 1;
    }
    if (!$neu || exists $neu->{punkte_pro_runde}) {
	hash_aktualisieren $callback, 'runde',
		[qw(id startnummer runde)], [qw(punkte)],
		[$id, $startnummer],
		punkte_pro_runde_hash($alt),
		punkte_pro_runde_hash($neu)
	    and $changed = 1;
    }
    if (!$neu || exists $neu->{wertungen}) {
	if ($alt && $neu) {
	    # Die Datenbank speichert Fließkommazahlen wahrscheinlich nicht mit
	    # derselben Genauigkeit, die Perl für die Berechnung verwendet.
	    my $eps = 1 / (1 << 13);
	    my $wp_alt = $alt->{wertungspunkte};
	    my $wp_neu = $neu->{wertungspunkte};
	    for (my $idx = 0; $idx < 4; $idx++) {
		if (defined $wp_alt->[$idx] && defined $wp_neu->[$idx] &&
		    abs($wp_alt->[$idx] - $wp_neu->[$idx]) < $eps) {
		    $wp_alt->[$idx] = $wp_neu->[$idx];
		}
	    }
	}

	hash_aktualisieren $callback, 'fahrer_wertung',
		[qw(id startnummer wertung)], [qw(wertungsrang wertungspunkte)],
		[$id, $startnummer],
		fahrer_wertungen_hash($alt),
		fahrer_wertungen_hash($neu)
	    and $changed = 1;
    }

    my $felder = [];
    my $felder_alt = $alt ? [] : undef;
    my $felder_neu = $neu ? [] : undef;
    if ($neu) {
	foreach my $feld (qw(
	    klasse helfer bewerber nenngeld nachname vorname strasse wohnort
	    plz club fahrzeug geburtsdatum telefon lizenznummer rahmennummer
	    kennzeichen hubraum bemerkung land bundesland helfer_nummer
	    startzeit zielzeit stechen nennungseingang papierabnahme
	    versicherung runden ausfall zusatzpunkte punkte rang)) {
	    if (exists $neu->{$feld}) {
		push @$felder, $feld;
		push @$felder_alt, $alt->{$feld}
		    if $alt;
		push @$felder_neu, $neu->{$feld};
	    }
	}
	if (exists $neu->{s}) {
	    for (my $n = 0; $n <= 4; $n++) {
		push @$felder, "s$n";
		push @$felder_alt, $alt->{s}[$n]
		    if $alt;
		push @$felder_neu, $neu->{s}[$n];
	    }
	}
    }

    my $version = $alt ? $alt->{version} : 0;
    datensatz_aktualisieren $callback, 'fahrer',
	    $versionierung ? \$version : undef, $changed,
	    [qw(id startnummer)], $felder,
	    [$id, $startnummer],
	    $felder_alt,
	    $felder_neu
	and $changed = 1;
    $neu->{version} = $version
	if $neu;
    return $changed;
}

sub fahrer_aktualisieren($$$$$) {
    my ($callback, $id, $alt, $neu, $versionierung) = @_;
    my $changed;

    my ($deletes, $updates, $inserts) =
	deletes_updates_inserts($alt, $neu);
    if (@$deletes) {
	foreach my $startnummer (@$deletes) {
	    einen_fahrer_aktualisieren $callback, $id, $alt->{$startnummer},
		    undef, $versionierung
		and $changed = 1;
	}
    }
    if (@$updates) {
	foreach my $startnummer (@$updates) {
	    einen_fahrer_aktualisieren $callback, $id, $alt->{$startnummer},
		    $neu->{$startnummer}, $versionierung
		and $changed = 1;
	}
    }
    if (@$inserts) {
	foreach my $startnummer (@$inserts) {
	    einen_fahrer_aktualisieren $callback, $id, undef,
		    $neu->{$startnummer}, $versionierung
		and $changed = 1;
	}
    }
    return $changed;
}

sub veranstaltung_wertungen_hash($) {
    my ($cfg) = @_;

    my $hash = {};
    if ($cfg && $cfg->{titel} && $cfg->{subtitel} && $cfg->{wertungen}) {
	for (my $n = 0; $n < @{$cfg->{titel}}; $n++) {
	    next if $cfg->{titel}[$n] eq "" && $cfg->{subtitel}[$n] eq "";
	    $hash->{$n + 1} = [$cfg->{titel}[$n], $cfg->{subtitel}[$n],
			       $cfg->{wertungen}[$n]];
	}
    }
    return $hash;
}

sub wertungspunkte_hash($$) {
    my ($cfg, $minimieren) = @_;

    my $hash = {};
    if ($cfg && $cfg->{wertungspunkte}) {
	my $n = @{$cfg->{wertungspunkte}} - 1;
	if ($minimieren) {
	    # Gleiche Werte am Ende der Tabelle zusammenfassen: der letzte Wert
	    # gilt für alle weiteren Plätze.
	    for (; $n > 0; $n--) {
		last unless $cfg->{wertungspunkte}[$n] ~~ $cfg->{wertungspunkte}[$n - 1];
	    }
	}
        for (; $n >= 0; $n--) {
	    my $wertungspunkte = $cfg->{wertungspunkte}[$n];
	    $hash->{$n + 1} = [$wertungspunkte]
		if defined $wertungspunkte;
        }
    }
    return $hash;
}

sub sektionen_hash($) {
    my ($cfg) = @_;

    my $hash = {};
    if ($cfg && $cfg->{sektionen}) {
	for (my $m = 0; $m < @{$cfg->{sektionen}}; $m++) {
	    for (my $n = 0; $n < length $cfg->{sektionen}[$m]; $n++) {
		next if substr($cfg->{sektionen}[$m], $n, 1) eq "N";
		$hash->{($m + 1) . ':' . ($n + 1)} = [];
	    }
	}
    }
    return $hash;
}

sub klassen_hash($$) {
    my ($cfg, $klassenfarben) = @_;

    my $hash = {};
    if ($cfg && $cfg->{runden} && $cfg->{klassen} &&
		$cfg->{fahrzeiten} && $cfg->{sektionen}) {
	my $gestartete_klassen = gestartete_klassen($cfg);
	for (my $n = 0; $n < @{$cfg->{klassen}}; $n++) {
	    my $farbe = defined $klassenfarben ? $klassenfarben->{$n + 1} : undef;
	    $hash->{$n + 1} = [$cfg->{runden}[$n], $cfg->{klassen}[$n],
			       $gestartete_klassen->[$n], $farbe,
			       $cfg->{fahrzeiten}[$n]];
	}
    }
    return $hash;
}

sub kartenfarben_hash($) {
    my ($cfg) = @_;

    my $hash = {};
    if ($cfg) {
	for (my $n = 0; $n < @{$cfg->{kartenfarben}}; $n++) {
	    my $farbe = $cfg->{kartenfarben}[$n];
	    next unless defined $farbe;
	    $hash->{$n + 1} = [$farbe];
	}
    }
    return $hash;
}

sub feature_hash($) {
    my ($cfg) = @_;

    my $hash = {};
    if ($cfg) {
	foreach my $feature (@{$cfg->{nennungsmaske_felder}}) {
	    $hash->{$feature} = [];
	}
    }
    return $hash;
}

sub vareihe_hash($) {
    my ($cfg) = @_;

    my $hash = {};
    if ($cfg) {
	foreach my $vareihe (@{$cfg->{vareihen}}) {
	    $hash->{$vareihe} = [];
	}
    }
    return $hash;
}

sub neue_startnummern_hash($) {
    my ($cfg) = @_;

    my $hash = {};
    if ($cfg) {
	my $neue_startnummern = $cfg->{neue_startnummern};
	foreach my $startnummer (keys %$neue_startnummern) {
	    $hash->{$startnummer} = [$neue_startnummern->{$startnummer}];
	}
    }
    return $hash;
}

sub veranstaltung_aktualisieren($$$$) {
    my ($callback, $id, $alt, $neu, $klassenfarben) = @_;
    my $changed;

    if (!$neu || (exists $neu->{titel} &&
		  exists $neu->{subtitel} &&
		  exists $neu->{wertungen})) {
	hash_aktualisieren $callback, 'wertung',
		[qw(id wertung)], [qw(titel subtitel bezeichnung)],
		[$id],
		veranstaltung_wertungen_hash($alt),
		veranstaltung_wertungen_hash($neu)
	    and $changed = 1;
    }
    if (!$neu || exists $neu->{wertungspunkte}) {
	hash_aktualisieren $callback, 'wertungspunkte',
		[qw(id rang)], [qw(punkte)],
		[$id],
		wertungspunkte_hash($alt, 0),
		wertungspunkte_hash($neu, 1)
	    and $changed = 1;
    }
    if (!$neu || exists $neu->{sektionen}) {
	hash_aktualisieren $callback, 'sektion',
		[qw(id klasse sektion)], [],
		[$id],
		sektionen_hash($alt),
		sektionen_hash($neu)
	    and $changed = 1;
    }

    if (!$neu || (exists $neu->{runden} && exists $neu->{klassen} &&
		  exists $neu->{fahrzeiten} && exists $neu->{sektionen})) {
	hash_aktualisieren $callback, 'klasse',
		[qw(id klasse)], [qw(runden bezeichnung gestartet farbe fahrzeit)],
		[$id],
		klassen_hash($alt, $klassenfarben),
		klassen_hash($neu, $klassenfarben)
	    and $changed = 1;
    }

    if (!$neu || exists $neu->{kartenfarben}) {
	hash_aktualisieren $callback, 'kartenfarbe',
		[qw(id runde)], [qw(farbe)],
		[$id],
		kartenfarben_hash($alt),
		kartenfarben_hash($neu)
	    and $changed = 1;
    }

    if (!$neu || exists $neu->{nennungsmaske_felder}) {
	hash_aktualisieren $callback, 'veranstaltung_feature',
		[qw(id feature)], [],
		[$id],
		feature_hash($alt),
		feature_hash($neu)
	    and $changed = 1;
    }

    if (!$neu || exists $neu->{vareihen}) {
	hash_aktualisieren $callback, 'vareihe_veranstaltung',
		[qw(id vareihe)], [],
		[$id],
		vareihe_hash($alt),
		vareihe_hash($neu)
	    and $changed = 1;
    }

    if (!$neu || exists $neu->{neue_startnummern}) {
	hash_aktualisieren $callback, 'neue_startnummer',
		[qw(id startnummer)], [qw(neue_startnummer)],
		[$id],
		neue_startnummern_hash($alt),
		neue_startnummern_hash($neu)
	    and $changed = 1;
    }

    my $felder = [];
    my $felder_alt = $alt ? [] : undef;
    my $felder_neu = $neu ? [] : undef;
    if ($neu) {
	foreach my $feld (qw(
	    dateiname datum aktiv vierpunktewertung wertungsmodus
	    punkte_sektion_auslassen wertungspunkte_234 rand_links rand_oben
	    wertungspunkte_markiert versicherung ergebnislistenbreite
	    ergebnisliste_feld dat_mtime cfg_mtime punkteteilung)) {
	    if (exists $neu->{$feld}) {
		push @$felder, $feld;
		push @$felder_alt, $alt->{$feld}
		    if $alt;
		push @$felder_neu, $neu->{$feld};
	    }
	}
    }

    my $version = $alt ? $alt->{version} : 0;
    datensatz_aktualisieren $callback, 'veranstaltung',
	    \$version, $changed,
	    [qw(id)], $felder,
	    [$id],
	    $felder_alt,
	    $felder_neu
	and $changed = 1;
    $neu->{version} = $version;
    return $changed;
}