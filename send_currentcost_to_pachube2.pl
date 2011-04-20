#!/usr/bin/perl -w
#
# Use 'send_currentcost_to_pachube.pl -q' for no output
#
my %config; my $conf = \%config;

# Read data from USB port using CurrentCost data cable
$conf->{serialport} = "/dev/ttyUSB0";

# Now you can configure multiple feeds

### feed 1
$conf->{feed1}{destination}="pachube"; # only known destination right now is "pachube";
$conf->{feed1}{apikey}="---enter-your-API-key-here----";
$conf->{feed1}{id}="----enter-your-feed-id-here----";
$conf->{feed1}{title}="Energy usage from CC128 via WL-500G";
$conf->{feed1}{website}="http://wiki.version6.net/pachube_currentcost";
$conf->{feed1}{descr}="CurrentCost CC128 data via ASUS WL500-G Premium serial port.

ID format is [SCC] where [S] is sensor number and [CC] is channel number.

CC=00 is total of all channels, CC=99 is temperature of sensor.";
$conf->{feed1}{locname}="Lonely island in the middle of nowhere";
$conf->{feed1}{loclat}="39.7113927178886";
$conf->{feed1}{loclon}="39.7113927178886";

$conf->{feed1}{sendrate} = 20;	# send data to pachube not more than 3 times in min

### feed 2
#$conf->{my_realtime_feed}{destination}="pachube"; # not in use if commented out
$conf->{my_realtime_feed}{apikey}="---enter-your-another-API-key-here----";
$conf->{my_realtime_feed}{id}="----enter-your-another-feed-id-here----";
$conf->{my_realtime_feed}{title}="Real Time Energy Usage From CC128 via WL-500G";
$conf->{my_realtime_feed}{website}="http://wiki.version6.net/pachube_currentcost";
$conf->{my_realtime_feed}{descr}="CurrentCost CC128 data via ASUS WL500-G Premium serial port.

ID format is [SCC] where [S] is sensor number and [CC] is channel number.

CC=00 is total of all channels, CC=99 is temperature of sensor.

This is real time feed i.e. every CC128 message will be posted here immediately";
#$conf->{my_realtime_feed}{locname}="Lonely island in the middle of nowhere";
#$conf->{my_realtime_feed}{loclat}="39.7113927178886";
#$conf->{my_realtime_feed}{loclon}="39.7113927178886";

$conf->{my_realtime_feed}{sendrate} = 0;	# send data to pachube in real time (every 6 sec)

### feed 3
# For example, to generate token (and path) for 4 variables, go to link like this:
# https://www.google.com/powermeter/device/activate?mfg=version6net&model=currentcost&did=1234567890&dvars=4&location=Alaska&title_0=L1&title_1=L2&title_2=L3&title_3=Total
# after that extract token and path from activation information
$conf->{powermeter_test}{destination}="powermeter";
$conf->{powermeter_test}{token}="---powermeter-token---";
$conf->{powermeter_test}{path}="---powermeter-path---";
$conf->{powermeter_test}{sensormap}={	# "<sensor number>:<channel number>" => <powermeter-variable-number>
	"0:1"		=>	1,
	"0:2"		=>	2,
	"0:3"		=>	3,
	"0:TOTAL"	=>	4,
};
$conf->{powermeter_test}{sendrate} = 600;	# send data to google powermeter in 10 min interval (default)


#############################################################################
#
# nothing to change after this line for normal users
#
# for developers, feel free to clone https://github.com/Cougar/pachube
#

use strict;
use LWP::UserAgent;
use XML::Simple qw(:strict);

$| = 1;

my $verbose = (defined $ARGV[0] && $ARGV[0] eq "-q") ? 0 : 1;

{ package Data::Channel;
	sub new {
		my $self = {};
		$self->{_id} = undef;
		$self->{_unit} = undef;
		$self->{_value} = undef;
		$self->{_timestamp} = undef;
		$self->{_start_time} = 0;
		$self->{_duration} = 0;		# 0 for snapshot
		$self->{_usage} = 0;		# SUM (_value x _duration)
		bless($self);
		return $self;
	}
	sub id {
		my $self = shift;
		if (@_) { $self->{_id} = shift }
		return $self->{_id};
	}
	sub unit {
		my $self = shift;
		if (@_) { $self->{_unit} = shift }
		return $self->{_unit};
	}
	sub value {
		my $self = shift;
		if (@_) { $self->{_value} = shift }
		return $self->{_value};
	}
	sub timestamp {
		my $self = shift;
		if (@_) {
			my $ts = shift;
			$self->{_timestamp} = $ts;
			if (! $self->start_time) {
				$self->start_time($ts);
			}
		}
		return $self->{_timestamp};
	}
	sub start_time {
		my $self = shift;
		if (@_) { $self->{_start_time} = shift }
		return $self->{_start_time};
	}
	sub duration {
		my $self = shift;
		if (@_) { $self->{_duration} = shift }
		return $self->{_duration};
	}
	sub usage {
		my $self = shift;
		if (@_) { $self->{_usage} = shift }
		return $self->{_usage};
	}
	sub add { # add sequental measurements
		my $self = shift;
		if (! @_) { die "\nmissing parameter" }
		my $param = shift;
		if ($self->id() != $param->id()) { die "\nchannel ids MUST match" }
		if ($self->unit() ne $param->unit()) { die "\nchannel units MUST match" }
		my $duration = $param->timestamp() - $self->timestamp();	# duration of old value
		$self->duration($self->duration() + $duration);			# increase duration
		$self->usage($self->usage() + ($self->value() * $duration));	# increase usage by last value times duration
		$self->value($param->value());					# copy new value
		$self->timestamp($param->timestamp());				# copy new timestamp
	}
	sub sum { # sum parallel measurements (used for total calculations)
		my $self = shift;
		if (! @_) { die "\nmissing parameter" }
		my $param = shift;
		if (defined $self->unit()) {
			if ($self->unit() ne $param->unit()) { die "\nchannel units MUST match" }
		} else {
			$self->unit($param->unit());
		}
		if (defined $self->timestamp()) {
			if ($self->timestamp() ne $param->timestamp()) { die "\nchannel timestamps MUST match" }
		} else {
			$self->timestamp($param->timestamp());
		}
		if ($self->start_time() > 0) {
			if ($self->start_time() ne $param->start_time()) { die "\nchannel start_times MUST match: " . $self->start_time() . " != " . $param->start_time(); }
		} else {
			$self->start_time($param->start_time());
		}
		if ($self->duration() > 0) {
			if ($self->duration() ne $param->duration()) { die "\nchannel durations MUST match" }
		} else {
			$self->duration($param->duration());
		}
		if (defined $self->value()) {
			$self->value($self->value() + $param->value());		# add values
		} else {
			$self->value($param->value());
		}
		if (defined $self->usage()) {
			$self->usage($self->usage() + $param->usage());		# add usages
		} else {
			$self->usage($param->usage());
		}
	}
	sub clone {
		my $self = shift;
		my $clone = $self->new();
		$clone->id($self->id());
		$clone->unit($self->unit());
		$clone->value($self->value());
		$clone->timestamp($self->timestamp());
		$clone->start_time($self->start_time());
		$clone->duration($self->duration());
		$clone->usage($self->usage());
		return $clone;
	}
	sub printVerbose {
		my $self = shift;
		return unless ($verbose);
		if (defined $self->id()) {
			printf("\n  C:%1d %5d W", $self->id(), $self->value());
		} else {
			printf("\n  SUM %5d W", $self->value());
		}
		if ($self->duration) {
			printf(" (%4d sec: %8d Ws (%5.2f kWh), avg %5d W)",
			       $self->timestamp - $self->start_time,
			       $self->usage,
			       $self->usage / 1000 / 3600,
			       $self->usage / $self->duration);
		}
	}
}

{ package Data::Sensor;
	sub new {
		my $self = {};
		$self->{_channels} = ();
		$self->{_id} = undef;
		$self->{_sensor} = undef;
		$self->{_tmpr} = undef;
		bless($self);
		return $self;
	}
	sub id {
		my $self = shift;
		if (@_) { $self->{_id} = shift }
		return $self->{_id};
	}
	sub sensor {
		my $self = shift;
		if (@_) { $self->{_sensor} = shift }
		return $self->{_sensor};
	}
	sub tmpr {
		my $self = shift;
		if (@_) { $self->{_tmpr} = shift }
		return $self->{_tmpr};
	}
	sub addChannel {
		my $self = shift;
		if (@_) { push(@{$self->{_channels}}, shift); }
		return $self->{_channels};
	}
	sub isChannel {
		my $self = shift;
		if (!@_) { die "\nid missing" }
		my $id = shift;

		if (! defined $self->{_channels}) {
			# no channels added yet
			return 0;
		}
		foreach my $channel ($self->listChannels()) {
			if ($channel->id() == $id) {
				return $channel;
			}
		}
		return 0;
	}
	sub removeChannels {
		my $self = shift;
		$self->{_channels} = undef;
	}
	sub listChannels {
		my $self = shift;
		return @{$self->{_channels}};
	}
	sub add {
		my $self = shift;
		if (!@_) { die "\nsensor missing" }
		my $sensor = shift;
		foreach my $channel ($sensor->listChannels()) {
			my $ourchannel = $self->isChannel($channel->id());
			if ($ourchannel) {
				# this channel exists in our sensor
				$ourchannel->add($channel);
			} else {
				# create new channel
				$self->isChannel($sensor->clone());
			}
		}
	}
	sub clone {
		my $self = shift;
		my $clone = $self->new();
		$clone->id($self->id());
		$clone->sensor($self->sensor());
		$clone->tmpr($self->tmpr());
		foreach my $channel ($self->listChannels()) {
			$clone->addChannel($channel->clone());
		}
		return $clone;
	}
	sub printVerbose {
		my $self = shift;
		return unless ($verbose);
		print "\n S:" . $self->sensor() . " T:" . $self->tmpr() . " I:" . $self->id();
		my $total;
		my $channels = 0;
		foreach my $i (0 .. (@{$self->{_channels}} - 1)) {
			$self->{_channels}[$i]->printVerbose();
			if (! $channels) {
				$total = $self->{_channels}[$i]->clone();
				$total->id(undef);
			} else {
				$total->sum($self->{_channels}[$i]);
			}
			$channels ++;
		}
		if ($channels > 1) {
			$total->printVerbose();
		}
	}
}

{ package Data::Network;
	sub new {
		my $self = {};
		$self->{_sensors} = ();
		$self->{_id} = undef;
		$self->{_name} = undef;
		bless($self);
		return $self;
	}
	sub id {
		my $self = shift;
		if (@_) { $self->{_id} = shift }
		return $self->{_id};
	}
	sub name {
		my $self = shift;
		if (@_) { $self->{_name} = shift }
		return $self->{_name};
	}
	sub addSensor {
		my $self = shift;
		if (@_) {
			my $sensor = shift;
			if (! $self->isSensor($sensor->id())) {
				push(@{$self->{_sensors}}, $sensor);
			}
		}
		return $self->{_sensors};
	}
	sub isSensor {
		my $self = shift;
		if (!@_) { die "\nid missing" }
		my $id = shift;

		if (! defined $self->{_sensors}) {
			# no sensors added yet
			return 0;
		}
		foreach my $sensor ($self->listSensors()) {
			if ($sensor->id() == $id) {
				return $sensor;
			}
		}
		return 0;
	}
	sub listSensors {
		my $self = shift;
		if (defined $self->{_sensors}) { return @{$self->{_sensors}}; }
	}
	sub removeSensors {
		my $self = shift;
		$self->{_sensors} = undef;
	}
	sub add {
		my $self = shift;
		if (!@_) { die "\nnetwork missing" }
		my $network = shift;
		foreach my $sensor ($network->listSensors()) {
			my $oursensor = $self->isSensor($sensor->id());
			if ($oursensor) {
				# this sensor exists in our network
				$oursensor->add($sensor);
			} else {
				# create new sensor
				$self->addSensor($sensor->clone());
			}
		}
	}
	sub clone {
		my $self = shift;
		my $clone = $self->new();
		$clone->id($self->id());
		$clone->name($self->name());
		foreach my $sensor ($self->listSensors()) {
			$clone->addSensor($sensor->clone());
		}
		return $clone;
	}
	sub printVerbose {
		my $self = shift;
		return unless ($verbose);
		print "\nI:" . $self->id() . " N:" . $self->name();
		foreach my $i (0 .. (@{$self->{_sensors}} - 1)) {
			$self->{_sensors}[$i]->printVerbose;
		}
	}
}

{ package DataReader::CC128;
	sub new {
		my $self = {};
		$self->{_dispatcher} = ();
		$self->{_network} = Data::Network->new();
		$self->{_network}->id(0); # only one network supported right now
		$self->{_network}->name("CurrentCost network");
		bless($self);
		return $self;
	}
	sub addNewDispatcher {
		my $self = shift;
		if (@_) { push(@{$self->{_dispatcher}}, shift); }
		return $self->{_dispatcher};
	}
	sub readLine {
		my $self = shift;
		my $line = shift;
		$line =~ s/\r\n //;

		my $datats = time();

		my $xs = XML::Simple->new(ForceArray => 0, KeyAttr => '');
		my $ccdata = $xs->XMLin($line);

		return if (! exists $ccdata->{type});	# sensor Type, "1" = electricity
		return if ($ccdata->{type} != 1);
		
		my $sensor = Data::Sensor->new();
		$sensor->id($ccdata->{id});		# radio ID received from the sensor
		$sensor->sensor($ccdata->{sensor});	# Appliance Number as displayed
		$sensor->tmpr($ccdata->{tmpr});		# temperature as displayed

		for (my $ch = 0; $ch < 9; $ch++) {
			next if (! exists $ccdata->{"ch" . $ch});	# sensor channel

			my $channel = Data::Channel->new();
			$channel->id($ch);
			$channel->timestamp($datats);

			# DOES NOT WORK IF THERE IS MORE THAN ONE UNIT
			foreach my $unit (sort (keys %{$ccdata->{"ch$ch"}})) {
				$channel->unit($unit);
				$channel->value($ccdata->{"ch$ch"}{$unit});
				$sensor->addChannel($channel);
			}
		}
		print "\nCC128 data read:" if ($verbose);
		$sensor->printVerbose();
		$self->{_network}->addSensor($sensor);
		foreach my $i (0 .. (@{$self->{_dispatcher}} - 1)) {
			$self->{_dispatcher}[$i]->processNetwork($self->{_network});
		}
		$self->{_network}->removeSensors();
	}
}

{ package Input::Serial;
	sub new {
		my $self = {};
		shift;
		$self->{_serialport} = "/dev/ttyS0";
		$self->{_datareader} = undef;
		if (@_) { $self->{_serialport} = shift }
		bless($self);
		return $self;
	}
	sub addNewDataReader {
		my $self = shift;
		if (@_) { push(@{$self->{_datareader}}, shift); }
		return $self->{_datareader};
	}
	sub run {
		my $self = shift;
		while (1) {
			# eval "use Device::SerialPort;";
			# die $@ if $@;
			# my $PortObj = Device::SerialPort->new($self->{serialport}) || return;
			# $PortObj->baudrate(57600);
			# $PortObj->write_settings;
			# undef $PortObj;
			open(SERIAL, "+>" . $self->{_serialport});
			while (<SERIAL>) {
				chomp;
				foreach my $i (0 .. (@{$self->{_datareader}} - 1)) {
					$self->{_datareader}[$i]->readLine($_);
				}
			}
			close SERIAL;
			sleep(1);
			print "\n reconnecting.. " if ($verbose);
		}
	}
}

{ package Input::TTY;
	sub new {
		my $self = {};
		$self->{_datareader} = undef;
		bless($self);
		return $self;
	}
	sub addNewDataReader {
		my $self = shift;
		if (@_) { push(@{$self->{_datareader}}, shift); }
		return $self->{_datareader};
	}
	sub run {
		my $self = shift;
		while (<>) {
			chomp;
			foreach my $i (0 .. (@{$self->{_datareader}} - 1)) {
				$self->{_datareader}[$i]->readLine($_);
			}
		}
	}
}

{ package Output::Dispatcher;
	sub new {
		my $self = {};
		$self->{_output} = undef;
		$self->{_output_rate} = 0;
		$self->{_last_send} = 0;		# use for network data collection
		$self->{_network_storage} = undef;	# network data for delayed sending
		bless($self);
		return $self;
	}
	sub addNewOutput {
		my $self = shift;
		if (@_) { push(@{$self->{_output}}, shift); }
		if (@_) { $self->{_output_rate} = shift }
		return $self->{_output};
	}
	sub _updateOutputs {
		my $self = shift;
		my $network = shift;
		foreach my $i (0 .. (@{$self->{_output}} - 1)) {
			$self->{_output}[$i]->updateOutput($network);
		}
	}
	sub processNetwork {
		my $self = shift;
		my $network = shift;

		if ($self->{_output_rate} == 0) {
			# real time update, no buffering
			$self->_updateOutputs($network);
			return;
		}

		# delayd update, work with local network data copy
		my $ts = time();

		if (! $self->{_last_send}) {
			# first time, no output update, build network data storage
			$self->{_last_send} = $ts;
			$self->{_network_storage} = $network->clone();
			return;
		}

		# add new data to the storage data
		$self->{_network_storage}->add($network);

		print "\nData storage for " . $self->{_output_rate} . " sec updates:" if ($verbose);
		$self->{_network_storage}->printVerbose();

		if (($ts - $self->{_last_send}) < $self->{_output_rate}) {
			# update is rate limited
			return;
		}

		# time to send update (based on storage data)
		$self->_updateOutputs($self->{_network_storage});
		$self->{_last_send} = $ts;
		$self->{_network_storage} = $network->clone();
	}
}

{ package Output::Pachube;

	our $creator = "http://wiki.version6.net/pachube_currentcost";

	sub new {
		my $self = {};
		shift;
		if (@_) { $self->{_config} = shift } else { die "\nconfig missing" }
		$self->{_apiurl} = "http://api.pachube.com/v2/feeds/" . $self->{_config}{id} . ".xml";
		bless($self);
		return $self;
	}
	sub updateOutput() {
		my $self = shift;
		my $network = shift;

		my $xmldata;
		$xmldata .= "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n ";
		$xmldata .= "<eeml xmlns=\"http://www.eeml.org/xsd/005\"" . 
			    " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"" .
			    " version=\"5\"" .
			    " xsi:schemaLocation=\"http://www.eeml.org/xsd/005" .
			    " http://www.eeml.org/xsd/005/005.xsd\">\n ";
		$xmldata .= "  <environment id=\"" . $self->{_config}{id} . "\" creator=\"" . $creator . "\">\n ";
		$xmldata .= "    <title>" .  $self->{_config}{title} . "</title>\n ";
		$xmldata .= "    <feed>" . $self->{_apiurl} . "</feed>\n ";
		$xmldata .= "    <status>live</status>\n ";
		$xmldata .= "    <description>" . $self->{_config}{descr} . "</description>\n ";
		$xmldata .= "    <website>" . $self->{_config}{website} . "</website>\n ";
		$xmldata .= "    <location domain=\"physical\" exposure=\"indoor\"" .
			    " disposition=\"fixed\">\n ";
		$xmldata .= "      <name>" . $self->{_config}{locname} . "</name>\n " if (defined $self->{_config}{locname});
		$xmldata .= "      <lat>" . $self->{_config}{loclat} . "</lat>\n " if (defined $self->{_config}{loclat} && defined $self->{_config}{loclon});
		$xmldata .= "      <lon>" . $self->{_config}{loclon} . "</lon>\n " if (defined $self->{_config}{loclat} && defined $self->{_config}{loclon});
		$xmldata .= "    </location>\n ";

		foreach my $sensor ($network->listSensors()) {
			my $totalchannel = undef;
			# channel feeds [Scc]
			foreach my $channel ($sensor->listChannels()) {
				my $id = ($sensor->sensor() + 1) * 100 + $channel->id();
				$xmldata .= $self->_genXmlChannelData($channel, $id, "channel" . $channel->id(), "CC128", "power");
				# add totals
				if (! defined $totalchannel) {
					$totalchannel = $channel->clone();
					$totalchannel->id(undef);
				} else {
					$totalchannel->sum($channel);
				}
			}
			# total feed [S00]
			if (scalar($sensor->listChannels()) > 1) {
				my $id = ($sensor->sensor() + 1) * 100;
				$xmldata .= $self->_genXmlChannelData($totalchannel, $id, "total", "CC128", "power");
			}
			# temperature feed [S99]
			if ($sensor->tmpr) {
				$xmldata .= "    <data id=\"" . (($sensor->sensor() + 1) * 100 + 99) . "\">\n ";
				$xmldata .= "      <tag>CC128</tag>\n ";
				# $xmldata .= "      <tag>currentcost</tag>\n ";
				$xmldata .= "      <tag>temperature</tag>\n ";
				# $xmldata .= "      <tag>thermometer</tag>\n ";
				$xmldata .= "      <value>" . $sensor->tmpr() . "</value>\n ";
				$xmldata .= "      <unit type=\"derivedSI\" symbol=\"°C\">Degrees Celsius</unit>\n ";
				$xmldata .= "    </data>\n ";
			}
		}

		$xmldata .= "  </environment>\n ";
		$xmldata .= "</eeml>\n ";

		$self->_sendXml($xmldata);
	}
	sub _genXmlChannelData {
		my $self = shift;
		my $channel = shift;
		my $id = shift;
		my @tags = @_;

		my $xmldata = "    <data id=\"" . $id . "\">\n ";
		foreach my $tag (@tags) {
			$xmldata .= "      <tag>" . $tag . "</tag>\n ";
		}
		if ((my $duration = $channel->duration())) {
			$xmldata .= "      <value>" . sprintf("%d", $channel->usage() / $duration) . "</value>\n ";
		} else {
			$xmldata .= "      <value>" . sprintf("%d", $channel->value()) . "</value>\n ";
		}
		$xmldata .= "      <unit type=\"derivedSI\" symbol=\"W\">Watt</unit>\n ";
		$xmldata .= "    </data>\n ";
		return $xmldata;
	}
	sub _sendXml {
		my $self = shift;
		my $xmldata = shift;

		print "\n sending XML for " . $self->{_config}{id} . " .." if ($verbose);

		my $ua = LWP::UserAgent->new;
		$ua->agent("corepower/0.1");
		$ua->default_header(
			"X-PachubeApiKey" => $self->{_config}{apikey},
			"Content-Type" => "application/xml; charset=utf-8");
		my $request = HTTP::Request->new(PUT => $self->{_apiurl});
		$request->content($xmldata);
		my $res = $ua->request($request);
		if (! $res->is_success) {
			print $res->status_line, "\n" if ($verbose);
			return 0;
		}
		print " sent" if ($verbose);
		return 1;
	}
}

{ package Output::GooglePowerMeter;
	use POSIX qw(strftime);

	our $uri = "https://www.google.com/powermeter/feeds";

	sub new {
		my $self = {};
		shift;
		if (@_) { $self->{_config} = shift } else { die "\nconfig missing" }
		$self->{_token} = $self->{_config}{token};
		$self->{_path} = $self->{_config}{path};
		$self->{_sensormap} = $self->{_config}{sensormap};
		bless($self);
		return $self;
	}
	sub updateOutput() {
		my $self = shift;
		my $network = shift;

		my $xmldata = "";

		$xmldata .= "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
		$xmldata .= "<feed xmlns=\"http://www.w3.org/2005/Atom\"\n" .
			    "      xmlns:meter=\"http://schemas.google.com/meter/2008\"\n" .
			    "      xmlns:batch=\"http://schemas.google.com/gdata/batch\">\n";

		foreach my $sensor ($network->listSensors()) {
			my $totalchannel = undef;
			my $totalvar = $self->{_sensormap}{ sprintf("%d:TOTAL", $sensor->sensor) };
			foreach my $channel ($sensor->listChannels()) {
				my $var = $self->{_sensormap}{ sprintf("%d:%d", $sensor->sensor, $channel->id) };
				next unless (defined $var);
				$xmldata .= $self->_genXmlChannelData($channel, $var, "C-" . $sensor->sensor . ":" . $channel->id . "-" . $var);
				next unless (defined $totalvar);
				# add totals only if needed
				if (! defined $totalchannel) {
					$totalchannel = $channel->clone();
					$totalchannel->id(undef);
				} else {
					$totalchannel->sum($channel);
				}
			}
			if ((scalar($sensor->listChannels()) > 1) && defined $totalvar) {
				$xmldata .= $self->_genXmlChannelData($totalchannel, $totalvar, "C-" . $sensor->sensor . ":TOTAL-" . $totalvar);
			}
		}
		$xmldata .= "</feed>\n";

		$self->_sendXml($xmldata);
	}
	sub _genXmlChannelData {
		my $self = shift;
		my $channel = shift;
		my $var = shift;
		my $id = shift;

		my $xmldata = "";
		$xmldata .= "  <entry xmlns=\"http://www.w3.org/2005/Atom\"\n" .
			    "      xmlns:meter=\"http://schemas.google.com/meter/2008\">\n";
		$xmldata .= "    <category scheme=\"http://schemas.google.com/g/2005#kind\"\n" .
			    "        term=\"http://schemas.google.com/meter/2008#durMeasurement\"/>\n";
		$xmldata .= "    <meter:subject>\n" .
			    "      " . $uri . $self->{_path} . ".d" . $var . "\n" .
			    "    </meter:subject>\n" .
			    "    <batch:id>" . $id . "</batch:id>\n" .
			    "    <meter:startTime meter:uncertainty=\"1.0\">" .  POSIX::strftime("%Y-%m-%dT%H:%M:%S.000Z", gmtime($channel->start_time)) . "</meter:startTime>\n" .
			    "    <meter:endTime meter:uncertainty=\"1.0\">" . POSIX::strftime("%Y-%m-%dT%H:%M:%S.000Z", gmtime($channel->start_time + $channel->duration)) . "</meter:endTime>\n" .
			    "    <meter:quantity meter:uncertainty=\"0.001\" meter:unit=\"kW h\">" . sprintf("%.3f", $channel->usage / 1000 / 3600) . "</meter:quantity>\n" .
			    "  </entry>\n";
		return $xmldata;
	}
	sub _sendXml {
		my $self = shift;
		my $xmldata = shift;

		print "\nGoogle PowerMeter XML:\n" . $xmldata if ($verbose);
		print "\nsending.." if ($verbose); open F, "| curl
		--insecure --request POST --data-binary \@- --header
		'Authorization: AuthSub token=\"" .  $self->{_token} .  "\"'
		--header 'Content-Type: application/atom+xml'
		https://www.google.com/powermeter/feeds/event"; print F
		$xmldata; close F; print "sent\n" if ($verbose);
	}
}

# set up new DataReader
my $datareader = DataReader::CC128->new();

# read configuration
foreach my $f (sort (keys %$conf)) {
	next unless (ref($conf->{$f}) eq "HASH");
	if (! defined $conf->{$f}{destination}) {
		print STDERR "WARNING: feed \"$f\" destination not defined, ignoring\n ";
		next;
	}

	if ($conf->{$f}{destination} eq "pachube") {
		my $dispatcher = Output::Dispatcher->new();
		my $output = Output::Pachube->new($conf->{$f});
		$dispatcher->addNewOutput($output, defined $conf->{$f}{sendrate} ? $conf->{$f}{sendrate} : 0);
		$datareader->addNewDispatcher($dispatcher);
	} elsif ($conf->{$f}{destination} eq "powermeter") {
		my $dispatcher = Output::Dispatcher->new();
		my $output = Output::GooglePowerMeter->new($conf->{$f});
		$dispatcher->addNewOutput($output, defined $conf->{$f}{sendrate} ? $conf->{$f}{sendrate} : 0);
		$datareader->addNewDispatcher($dispatcher);
	} else {
		print STDERR "WARNING: feed \"$f\" destination \"" . $conf->{$f}{destination} . "\"is unknown, ignoring\n ";
		next;
	}
}

my $input;

if (defined $conf->{serialport}) {
	$input = Input::Serial->new($conf->{serialport});
	$input->addNewDataReader($datareader);
} else {
	print STDERR "You should configure 'serialport'\n";
	print STDERR "reading data from STDIN now..\n";
	$input = Input::TTY->new();
	$input->addNewDataReader($datareader);
	exit;
}

$input->run();
