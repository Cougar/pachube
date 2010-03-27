#!/usr/bin/perl -w
#
# Use 'send_currentcost_to_pachube.pl -q' for no output
#
my %config; my $conf = \%config;

# Define either this to read data from USB port using CurrentCost data cable ..
$conf->{serialport} = "/dev/ttyUSB0";
# .. or these to read CC128 data from CoreCard (via canDaemon) ..
#$conf->{candaemonhost}="----enter-your-candaemon-host-IP-or-name-here----";
#$conf->{candaemonport}="1200";
#$conf->{sns_Serial_ID}="01";

$conf->{apikey}="---enter-your-API-key-here----";
$conf->{id}="----enter-your-feed-id-here----";
$conf->{title}="Energy usage from CC128 via CoreCard";
$conf->{website}="http://wiki.version6.net/pachube_corecard_currentcost";
$conf->{descr}="CurrentCost CC128 data via CoreCard serial module.

ID format is [SCC] where [S] is sensor number and [CC] is channel number.

CC=00 is total of all channels, CC=99 is temperature of sensor.";
$conf->{locname}="Lonely island in the middle of nowhere";
$conf->{loclat}="39.7113927178886";
$conf->{loclon}="-31.1134557717014";

$conf->{xmlsendrate} = 60;	# send data to pachube every min

#############################################################################
# nothing to change after this line for normal users

my $url="http://www.pachube.com/api/feeds/" . $conf->{id} . ".xml";
my $creator="http://wiki.version6.net/pachube_corecard_currentcost";

use strict;
use LWP::UserAgent;
use XML::Simple;

$| = 1;

my $lastupdatets = time();

my %sec;	# time of available data in seconds for each ID
my %ws;		# watt x sec = kwh * 1000 * 3600 for each ID
my %lastwatts;	# last reading of watts for each ID
my %lastts;	# timestamp of last update for each ID
my %lastxmlts;	# timestamp of last pachube update for each ID

my $verbose = (defined $ARGV[0] && $ARGV[0] eq "-q") ? 0 : 1;

my %sensors;

sub send_xml_to_pachube()
{
	my ($xmldata) = @_;

	print "\nsending XML.." if ($verbose);

	my $ua = LWP::UserAgent->new;
	$ua->agent("corepower/0.1");
	$ua->default_header(
		"X-PachubeApiKey" => $conf->{apikey},
		"Content-Type" => "application/xml; charset=utf-8");
	my $request = HTTP::Request->new(PUT => $url);
	$request->content($xmldata);
	my $res = $ua->request($request);
	if (! $res->is_success) {
		print $res->status_line, "\n" if ($verbose);
                return 0;
	}
	print " sent  " if ($verbose);
	return 1;
}

sub generate_xml()
{
	my ($sensorref, $temp) = @_;
	my $xmldata;
	$xmldata .= "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
	$xmldata .= "<eeml xmlns=\"http://www.eeml.org/xsd/005\"" . 
	            " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"" .
	            " version=\"5\"" .
	            " xsi:schemaLocation=\"http://www.eeml.org/xsd/005" .
	            " http://www.eeml.org/xsd/005/005.xsd\">\n";
	$xmldata .= "  <environment id=\"$conf->{id}\" creator=\"" . $creator . "\">\n";
	$xmldata .= "    <title>" . $conf->{title} . "</title>\n";
	$xmldata .= "    <feed>" . $url . "</feed>\n";
	$xmldata .= "    <status>live</status>\n";
	$xmldata .= "    <description>" . $conf->{descr} . "</description>\n";
	$xmldata .= "    <website>" . $conf->{website} . "</website>\n";
	$xmldata .= "    <location domain=\"physical\" exposure=\"indoor\"" .
		    " disposition=\"fixed\">\n";
	$xmldata .= "      <name>" . $conf->{locname} . "</name>\n" if (defined $conf->{locname});
	$xmldata .= "      <lat>" . $conf->{loclat} . "</lat>\n" if (defined $conf->{loclat} && defined $conf->{loclon});
	$xmldata .= "      <lon>" . $conf->{loclon} . "</lon>\n" if (defined $conf->{loclat} && defined $conf->{loclon});
	$xmldata .= "    </location>\n";
	foreach my $sensor (sort(keys %$sensorref)) {
		$xmldata .= "    <data id=\"$sensor\">\n";
		$xmldata .= "      <tag>CoreCard</tag>\n";
		$xmldata .= "      <tag>CC128</tag>\n";
		if ($sensor % 100 == 99) {
			$xmldata .= "      <tag>temperature</tag>\n";
			$xmldata .= "      <tag>thermometer</tag>\n";
			$xmldata .= "      <value>$sensorref->{$sensor}</value>\n";
			$xmldata .= "      <unit type=\"derivedSI\" symbol=\"°C\">" .
			            "Degrees Celsius</unit>\n";
		} else {
			$xmldata .= "      <tag>electricity</tag>\n";
			$xmldata .= "      <tag>power</tag>\n";
			$xmldata .= "      <tag>watts</tag>\n";
			if ($sensor % 100 == 0) {
				$xmldata .= "      <tag>total</tag>\n";
			} else {
				$xmldata .= "      <tag>channel" . ($sensor % 100). "</tag>\n";
			}
			$xmldata .= "      <value>$sensorref->{$sensor}</value>\n";
			$xmldata .= "      <unit type=\"derivedSI\" symbol=\"W\">" .
		            "Watt</unit>\n";
		}
		$xmldata .= "    </data>\n";
	}
	$xmldata .= "  </environment>\n";
	$xmldata .= "</eeml>\n";
	return $xmldata;
}

sub collect_sensor_data()
{
	my ($_) = @_;
	s/\r\n//;
	my $ccdata = eval { XMLin($_) };
	if ($@) {
		print " [XML parse error] ";
		return;
	}

	return if (! exists $ccdata->{type});
	return if ($ccdata->{type} != 1);

	my $datats = time();

	my $sensor = $ccdata->{sensor};
	my $temp = $ccdata->{tmpr};
	my $id = $ccdata->{id};
	printf("\nS:$sensor T:$temp I:$id") if ($verbose);

	my $totchid = ($sensor + 1) * 100 + 0;
	my $totwatts = 0;
	my $tottime = 0;

	$ws{$totchid} = 0;
	$sec{$totchid} = 0;

	my $channels = 0;
	for (my $ch = 0; $ch < 9; $ch++) {
		next if (! exists $ccdata->{"ch" . $ch});
                $channels++;
		my $chid = ($sensor + 1) * 100 + $ch;
		my $watts = $ccdata->{"ch$ch"}->{watts};
		printf("\n   C:%2d %5d W ", $ch, $watts) if ($verbose);
		$totwatts += $watts;
		if (! exists $lastwatts{$chid}) {	# first reading
		        $lastwatts{$chid} = $watts;
		        $lastts{$chid} = $datats;
		        $lastxmlts{$chid} = $datats;
		        next;
                }
                $ws{$chid} += $lastwatts{$chid} * ($datats - $lastts{$chid});
                $sec{$chid} += ($datats - $lastts{$chid});
                $tottime += ($datats - $lastts{$chid});
                $lastwatts{$chid} = $watts;
                $lastts{$chid} = $datats;

                if ($verbose && (defined $sec{$chid}) && ($sec{$chid} > 0)) {
        		printf("(since last update: %8d Ws, avg %5d W) ",
        		       $ws{$chid},
        		       $ws{$chid} / $sec{$chid});
                }
		$ws{$totchid} += $ws{$chid};
		$sec{$totchid} += $sec{$chid};
	}
	if ($verbose && ($channels > 1)) {
		printf("\nAVERAGE %5d W ", $totwatts / $channels);
		if ($sec{$totchid} > 0) {
        		printf("(since last update: %8d Ws, avg %5d W) ",
        		       $ws{$totchid} / $channels,
        		       $ws{$totchid} / $sec{$totchid});
                }
		printf("\n  TOTAL %5d W ", $totwatts);
		if ($sec{$totchid} > 0) {
        		printf("(since last update: %8d Ws, avg %5d W) ",
        		       $ws{$totchid},
        		       $ws{$totchid} / $sec{$totchid} * $channels);
                }
	}

	return if (($datats - $lastupdatets) < $conf->{xmlsendrate});

	foreach my $chid (keys %ws) {
	        next if (! defined $lastxmlts{$chid});
		if ($lastts{$chid} < $datats) {	# no update but ned to calculate
		        $ws{$chid} += $lastwatts{$chid} * ($datats - $lastts{$chid});
                        $sec{$chid} += ($datats - $lastts{$chid});
		        $lastts{$chid} = $datats;
		}
		$sensors{$chid} = sprintf("%d", $ws{$chid} / $sec{$chid});
	}

	$sensors{($sensor + 1) * 100 + 99} = $temp;

	if (&send_xml_to_pachube(&generate_xml(\%sensors))) {
        	$lastupdatets = $datats;
        	undef %ws;
        	undef %sec;
        }
	undef %sensors;
}

sub read_data_from_candaemon()
{
	eval "use IO::Socket;";
	die $@ if $@;

	print "connecting to candaemon.." if ($verbose);
	my $sock = IO::Socket::INET->new(
		Proto => "tcp",
		Timeout => 1,
		PeerAddr => $conf->{candaemonhost},
		PeerPort => $conf->{candaemonport}); 	
	print " connected\n" if ($verbose);

	# Use 56000 instead of 57600 due U2X calculation error (20 MHz clock)
	print "set serial port speed to 56k\n";
	print $sock "PKT 1b302081 1 0 c0 da 00\n";

	my $line="";
	while (<$sock>) {
		chomp;
		if (! /^PKT ([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2}) 1 0(( [0-9a-f]{2})+)$/) {
			print "?" if ($verbose);# not a packet, what is it?
			next;
		}
		print "." if ($verbose);
		next unless ($1 eq "1a");	# CAN_MODULE_CLASS_SNS << 1 | DIRECTIONFLAG_TO_OWNER
		next unless ($2 eq "30");	# CAN_MODULE_TYPE_SNS_SERIAL
		next unless ($3 eq $conf->{sns_Serial_ID});
		next unless ($4 eq "80");	# CAN_MODULE_CMD_SERIAL_SERIALDATA
		my $data = $5;
		while ($data =~ / ([0-9a-f]{2})(.*)/) {
			$line .= chr(hex($1));
			$data = $2;
		}
		if ($line =~ /\r\n$/) {
			&collect_sensor_data($line) if ($line =~ /\r\n$/);
			$line = "";
		}
	}
}

sub read_data_from_serial()
{
	eval "use Device::SerialPort;";
	die $@ if $@;

	my $PortObj = Device::SerialPort->new($conf->{serialport}) || return;
	$PortObj->baudrate(57600);
	$PortObj->write_settings;

	open(SERIAL, "+>$conf->{serialport}");
	print " connected\n" if ($verbose);
	while (<SERIAL>) {
		chomp;
		&collect_sensor_data($_);
	}
	close SERIAL;
	undef $PortObj;
}

while (1) {
	if (defined $conf->{serialport}) {
		&read_data_from_serial();
	} elsif (defined $conf->{candaemonhost} &&
	         defined $conf->{candaemonport} &&
	         defined $conf->{sns_Serial_ID}) {
		&read_data_from_candaemon();
	} else {
		print STDERR "You should configure either 'serialport' or " .
		             "'candaemonhost', 'candaemonport' and 'sns_Serial_ID'\n";
		exit;
	}
	sleep(1);
	print "\nreconnecting.. " if ($verbose);
}
