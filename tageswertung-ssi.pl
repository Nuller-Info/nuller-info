#! /usr/bin/perl -w

use CGI;
use DBI;
use RenderOutput;
use Wertungen qw(tageswertung);
use strict;

my $database = 'mysql:mydb;mysql_enable_utf8=1';
my $username = 'auswertung';
my $password = '3tAw4oSs';

my $dbh = DBI->connect("DBI:$database", $username, $password)
    or die "Could not connect to database: $DBI::errstr\n";

my $q = CGI->new;
my $id = $q->param('id'); # veranstaltung
my $wereihe = $q->param('wertungsreihe');

# FIXME: Vernünftiges Verhalten, wenn $id oder $wereihe nicht gefunden

my $bezeichnung;
my $wertung;
my $cfg;
my $fahrer_nach_startnummer;
my $sth;

print "Content-type: text/html; charset=utf-8\n\n";

$sth = $dbh->prepare(q{
    SELECT bezeichnung
    FROM wereihe
    WHERE wereihe = ?
});
$sth->execute($wereihe);
($bezeichnung) = $sth->fetchrow_array;

unless (defined $bezeichnung) {
    doc_h1 "Wertungsreihe nicht gefunden.";
    exit;
}

$sth = $dbh->prepare(q{
    SELECT wertung, titel
    FROM wertung
    JOIN vareihe_veranstaltung USING (id)
    JOIN vareihe USING (vareihe, wertung)
    JOIN wereihe USING (vareihe)
    WHERE id = ? AND wereihe = ?
});
$sth->execute($id, $wereihe);
if (my @row = $sth->fetchrow_array) {
    $wertung = $row[0] - 1;
    $cfg->{titel}[$wertung] = $row[1];
}

unless (defined $cfg) {
    doc_h1 "Veranstaltung nicht gefunden.";
    exit;
}

$sth = $dbh->prepare(q{
    SELECT klasse, runden, bezeichnung
    FROM klasse
    JOIN wereihe_klasse USING (klasse)
    WHERE id = ? AND wereihe = ?
    ORDER BY klasse
});
$sth->execute($id, $wereihe);
while (my @row = $sth->fetchrow_array) {
    $cfg->{runden}[$row[0] - 1] = $row[1];
    $cfg->{klassen}[$row[0] - 1] = $row[2];
}

$sth = $dbh->prepare(q{
    SELECT klasse, rang, startnummer, nachname, vorname, zusatzpunkte,
	   s0, s1, s2, s3, punkte, wertungspunkte, runden, ausfall,
	   papierabnahme
    FROM fahrer
    JOIN fahrer_wertung USING (id, startnummer)
    JOIN vareihe_veranstaltung USING (id)
    JOIN wereihe USING (vareihe)
    JOIN wereihe_klasse USING (wereihe, klasse)
    JOIN vareihe USING (vareihe, wertung)
    WHERE id = ? AND wereihe = ?
});
$sth->execute($id, $wereihe);
while (my $fahrer = $sth->fetchrow_hashref) {
    my $startnummer = $fahrer->{startnummer};
    $fahrer->{os_1s_2s_3s} = [ $fahrer->{s0}, $fahrer->{s1},
			       $fahrer->{s2}, $fahrer->{s3} ];
    my $w;
    $w->[$wertung] = $fahrer->{wertungspunkte};
    $fahrer->{wertungspunkte} = $w;
    map { delete $fahrer->{$_} } qw(s0 s1 s2 s3);
    $fahrer_nach_startnummer->{$startnummer} = $fahrer;
}

$sth = $dbh->prepare(q{
    SELECT startnummer, runde, runde.punkte
    FROM runde
    JOIN fahrer USING (id, startnummer)
    JOIN vareihe_veranstaltung USING (id)
    JOIN wereihe USING (vareihe)
    JOIN wereihe_klasse USING (wereihe, klasse)
    WHERE id = ? and wereihe = ?
});
$sth->execute($id, $wereihe);
while (my @row = $sth->fetchrow_array) {
    my $fahrer = $fahrer_nach_startnummer->{$row[0]};
    $fahrer->{punkte_pro_runde}[$row[1] - 1] = $row[2];
}

$RenderOutput::html = 1;

#use Data::Dumper;
#print Dumper($cfg, $fahrer_nach_startnummer);

doc_h1 "$bezeichnung";
doc_h2 doc_text "$cfg->{titel}[$wertung]";
tageswertung $cfg, $fahrer_nach_startnummer, $wertung;
