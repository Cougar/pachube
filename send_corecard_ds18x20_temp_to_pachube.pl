#!/usr/bin/perl -w
#
# Use 'send_corecard_ds18x20_temp_to_pachube.pl -q' for no output
#

my $candaemonhost="----enter-your-candaemon-host-IP-or-name-here----";
my $candaemonport="1200";
my $sns_ds18x20_ID="01";

my $apikey="---enter-your-API-key-here----";
my $id="----enter-your-feed-id-here----";
my $title="Temperature from CoreCard";
my $website="http://wiki.version6.net/pachube_corecard_temperature";
my $descr="CoreCard sns_DS18x20 data from CanDaemon";
my $locname="Lonely island in the middle of nowhere";
my $loclat="39.7113927178886";
my $loclon="-31.1134557717014";

my $maxsendrate = 15;   # at least 15 sec between updates
                        # sns_ds18x20_ReportInterval default is 20 sec

#############################################################################
# nothing to change after this line for normal users

my $url="http://www.pachube.com/api/feeds/" . $id . ".xml";
my $creator="http://wiki.version6.net/pachube_corecard_temperature";

use strict;
use IO::Socket;
use LWP::UserAgent;

$| = 1;
my $lastts = 0;
my $verbose = (defined $ARGV[0] && $ARGV[0] eq "-q") ? 0 : 1;

sub send_xml_to_pachube()
{
        my ($xmldata) = @_;

        print "\nsending XML.." if ($verbose);

        my $ts = time();
        if (($ts - $lastts) < $maxsendrate) {
                print " ratelimited by \$maxsendrate (" . 
                        ($ts - $lastts) .
                        " < $maxsendrate)\n" if ($verbose);
                return;
        }
        $lastts = $ts;

        my $ua = LWP::UserAgent->new;
        $ua->agent("coretemp/0.2");
        $ua->default_header(
                "X-PachubeApiKey" => $apikey,
                "Content-Type" => "application/xml; charset=utf-8");
        my $request = HTTP::Request->new(PUT => $url);
        $request->content($xmldata);
        my $res = $ua->request($request);
        if (! $res->is_success) {
                print $res->status_line, "\n" if ($verbose);
        }
        print " sent  " if ($verbose);
}

sub generate_xml()
{
        my ($sensorref) = @_;
        my $xmldata;
        $xmldata .= "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
        $xmldata .= "<eeml xmlns=\"http://www.eeml.org/xsd/005\"" . 
                    " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"" .
                    " version=\"5\"" .
                    " xsi:schemaLocation=\"http://www.eeml.org/xsd/005" .
                    " http://www.eeml.org/xsd/005/005.xsd\">\n";
        $xmldata .= "  <environment id=\"$id\" creator=\"" . $creator . "\">\n";
        $xmldata .= "    <title>" . $title . "</title>\n";
        $xmldata .= "    <feed>" . $url . "</feed>\n";
        $xmldata .= "    <status>live</status>\n";
        $xmldata .= "    <description>" . $descr . "</description>\n";
        $xmldata .= "    <website>" . $website . "</website>\n";
        $xmldata .= "    <location domain=\"physical\" exposure=\"indoor\"" .
                    " disposition=\"fixed\">\n";
        $xmldata .= "      <name>" . $locname . "</name>\n" if (defined $locname);
        $xmldata .= "      <lat>" . $loclat . "</lat>\n" if (defined $loclat && defined $loclon);
        $xmldata .= "      <lon>" . $loclon . "</lon>\n" if (defined $loclat && defined $loclon);
        $xmldata .= "    </location>\n";
        foreach my $sensor (keys %$sensorref) {
                $xmldata .= "    <data id=\"$sensor\">\n";
                $xmldata .= "      <tag>CoreCard</tag>\n";
                $xmldata .= "      <tag>celsius</tag>\n";
                $xmldata .= "      <tag>temperature</tag>\n";
                $xmldata .= "      <tag>thermometer</tag>\n";
                $xmldata .= "      <value>$sensorref->{$sensor}</value>\n";
                $xmldata .= "      <unit type=\"derivedSI\" symbol=\"°C\">" .
                            "Degrees Celsius</unit>\n";
                $xmldata .= "    </data>\n";
        }
        $xmldata .= "  </environment>\n";
        $xmldata .= "</eeml>\n";
        return $xmldata;
}

print "connecting to candaemon.." if ($verbose);
my $sock = IO::Socket::INET->new(
        Proto => "tcp",
        Timeout => 1,
        PeerAddr => $candaemonhost,
        PeerPort => $candaemonport);    
print " ok\n" if ($verbose);

my %sensors;
while (<$sock>) {
        chomp;
        if (! /^PKT ([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2}) 1 0(( [0-9a-f]{2})+)$/) {
                print "?" if ($verbose);# not a packet, what is it?
                next;
        }
        print "." if ($verbose);
        next unless ($1 eq "1b");       # CAN_MODULE_CLASS_SNS << 1 | DIRECTIONFLAG_FROM_OWNER
        next unless ($2 eq "03");       # CAN_MODULE_TYPE_SNS_DS18X20
        next unless ($3 eq $sns_ds18x20_ID);
        next unless ($4 eq "41");       # CAN_MODULE_CMD_PHYSICAL_TEMPERATURE_CELSIUS
        if ($5 !~ /^ ([0-9a-f]{2}) ([0-9a-f]{2}) ([0-9a-f]{2})$/) {
                print "E" if ($verbose);# format error
                next;
        }

        my $sensorid = hex($1);
        my $word = hex("$2$3");
        my $temperature = (($word & 0x8000) ? -1 : 1) * (($word & 0x7FC0) >> 6)
                        + (($word & 0x003F) / 64);

        if (!exists $sensors{$sensorid}) {
                print "\nSensorId=${sensorid} Value=${temperature}  " if ($verbose);
                $sensors{$sensorid} = $temperature;
                next;
        }
        &send_xml_to_pachube(&generate_xml(\%sensors));
        undef %sensors;
        print "\nSensorId=${sensorid} Value=${temperature}  " if ($verbose);
        $sensors{$sensorid} = $temperature;
}