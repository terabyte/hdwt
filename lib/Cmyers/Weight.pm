##############################################################################
#
# Cmyers::Weight
#
# Description: Module for tracking weight loss/gain
#
# vi: ft=perl
#
##############################################################################

package Cmyers::Weight;

use strict;
use warnings;

use Date::Parse;
use Readonly;
use FreezeThaw qw(freeze thaw);
#use Chart::Gnuplot;
use Cmyers::Gnuplot;
use Data::Dumper;

Readonly my $DEFAULT_ARGS => {
    'halfLife' => 7*24*60*60, # data decay halflife, in seconds
    'defaultStartOffset' => -1*30*24*60*60, # 1 month ago
    'defaultEndOffset' => 0, # 10 seconds in the future
    'defaultHeight' => 768,
    'defaultWidth' => 1400,
    'dbFile' => 'weight.db',
    'printData' => 0,
    'startDate' => undef,
    'endDate' => undef,
    '_db' => {
        'weight' => {},
        'ema' => {},
    },
};

# TODO: readonly this?
my $NUM_SORT = sub {
    return ($a <=> $b);
};

sub new {
    my ($class, $args) = @_;

    my $this = bless {}, $class;
    $this->_parseArgs($args);

    return $this;
}

sub _parseArgs {
    my ($this, $args) = @_;

    foreach my $arg ( sort keys %{$DEFAULT_ARGS} ) {
        $this->{$arg} = $DEFAULT_ARGS->{$arg};
    }

    foreach my $arg ( sort keys %{$args} ) {
        $this->{$arg} = $args->{$arg};
    }
}

####
## Public Methods
####

sub graph {
    my ($this, $file) = @_;

    $this->_generateGraph($file);
}

sub readDB {
    my ($this) = @_;

    $this->_readDB($this->{'dbFile'});
}

sub writeDB {
    my ($this) = @_;

    $this->_writeDB($this->{'dbFile'})
}

sub recalculateAll {
    my ($this) = @_;

    $this->_recalculateAll();
}

# time = epoch seconds
# value = weight in unit of choice (probably lbs)
sub addDataPoint {
    my ($this, $time, $value) = @_;

    my $parsedTime = str2time($time);
#    print "Parsed Time: $parsedTime\n";
    $this->{'_db'}->{'weight'}->{$parsedTime} = $value;
    # when a point is added, any points after it must be recalculated.
    $this->_calculateAtTime($parsedTime);
}

sub readSimpleFile {
    my ($this, $file) = @_;

    open(my $FH, '<', $file) or die "Unable to open $file: $!\n";

    my $count = 0;
    while (my $line = <$FH>) {
        ++$count;
        my ($weight, $date);
        if ($line =~ m/([^ ]+) (.*)/) {
            ($weight, $date) = ($1, $2);
            my $time = str2time($date);

            print "Parsed Point: ($time, $weight)\n";

            $this->addDataPoint($time, $weight);
            next;
        }

        print"ParseWarning: Unable to parse line $count: '$line'\n";
    }
}

####
## Private Methods
####

sub _generateGraph {
    my ($this, $file) = @_;

    # put the data in nested array format:
    my $weightMatrix = [];
    my $weightDB = $this->{'_db'}->{'weight'};
    my $emaMatrix = [];
    my $emaDB = $this->{'_db'}->{'ema'};

    my $timeData = [];
    my $weightData = [];
    my $emaData = [];
   
    my $minTime;
    my $maxTime = 0;
    foreach my $time ( sort $NUM_SORT keys %{$weightDB} ) {
        $minTime ||= $time;
        $maxTime = $time if ($time > $maxTime);

        push @{$timeData}, $time;
        push @{$weightData}, $weightDB->{$time};
        push @{$emaData}, $emaDB->{$time};

    }

    my ($startDate, $endDate) = $this->_getDateRange();
    my $xtics = $this->_getXTics($startDate, $endDate);

    if ( $this->{'printData'} ) {
        foreach my $time ( sort $NUM_SORT keys %{$weightDB} ) {
            next if ($time < $startDate);
            next if ($time > $endDate);
            my $weight = $weightDB->{$time};
            my $ema = $emaDB->{$time};
            print "$time: $weight $ema\n";
        }
    }

    # One way to determine width is dynamically
    #my $xsize = scalar @{$timeData} * 15; # 15px per data point
    # Another way is fixed
    my $xsize = $this->{'defaultWidth'};
    my $ysize = $this->{'defaultHeight'};

    my $fakeXSize = $xsize / 720; # given in terms of default width, which I think is this.
    my $fakeYSize = $ysize / 504; # given in terms of default height, which I think is this.

    my $chart = Cmyers::Gnuplot->new(
        'output' => $file,
        'title' => 'Weight Data',
        'xlabel' => 'Date',
        'ylabel' => 'Weight (lbs)',
        'xrange' => [$startDate, $endDate],
        'imagesize' => "$fakeXSize, $fakeYSize",
        'timeaxis' => 'x',
        'xtics' => {
            'labelfmt' => '%b-%d',
            'labels' => $xtics,
            'minor' => 7,
        },
        'timestamp' => 'on',
        'grid' => {
            'type' => 'dash',
            'width' => 1,
        },
        # Custom implemented options
        'fillstyle' => 'solid 1.0 noborder',

    );

    my $weightDataSet = Chart::Gnuplot::DataSet->new(
        'xdata' => $timeData,
        'ydata' => $weightData,
        'style' => 'linespoints',
        'color' => '#00BB00',
        'width' => 1,
        'pointtype' => 13,
        'pointsize' => 2,
        'timefmt' => '%s',
    );

    my $emaDataSet = Chart::Gnuplot::DataSet->new(
        'xdata' => $timeData,
        'ydata' => $emaData,
        'style' => 'lines',
        'linetype' => 1,
        'color' => '#000033',
        'width' => 1,
        'timefmt' => '%s',
    );

#    my $above = Chart::Gnuplot::DataSet->new(
#        'xdata' => $timeData,
#        'ydata' => $emaData,
#        'style' => 'lines',
#        'linetype' => 1,
#        'color' => '#000033',
#        'width' => 1,
#        'timefmt' => '%s',
#    );

#    $above->{'style'} = 'filledcurves above';

    $chart->plot2d($weightDataSet, $emaDataSet); #, $above);

}

sub _getXTics {
    my ($startDate, $endDate) = @_;

    # 1281338014 is a monday
    # if $date / (24*60*60) % 7 == 3, it is a Sunday.
    my $xTics = [];
    my $curDate = $startDate;
    while ($curDate < $endDate ) {
        if ($curDate / (24*60*60) % 7 == 3) {
            push @{$xTics}, $curDate;
        }
        $curDate += 24*60*60;
    }
    return $xTics;
}

sub _getDateRange {
    my ($this) = @_;

    my $startDate = $this->{'startDate'};
    my $endDate = $this->{'endDate'};

    return ($startDate, $endDate) if ($startDate && $endDate);

    # get latest data point
    my $weightDB = $this->{'_db'}->{'weight'};
    my $max = 0;
    foreach my $key ( sort $NUM_SORT keys %{$weightDB} ) {
        $max = $key;
    }

    if ( ! defined $startDate ) {
        $startDate = $max + $this->{'defaultStartOffset'};
    }
    if ( ! defined $endDate ) {
        # default to tomorrow
        $endDate = $max + $this->{'defaultEndOffset'};
    }

    print "Using '$startDate' and '$endDate'\n";
    return ($startDate, $endDate);
}

sub _recalculateAll {
    my ($this) = @_;

    my $weightDB = $this->{'_db'}->{'weight'};
    foreach my $key ( sort $NUM_SORT keys %{$weightDB} ) {
        $this->_calculatePoint($key);
    }
}

sub _calculateAtTime {
    my ($this, $time) = @_;

    my $weightDB = $this->{'_db'}->{'weight'};
    foreach my $key ( sort $NUM_SORT keys %{$weightDB} ) {
        next if ( $key < $time );

        # these points need to be recalculated
        $this->_calculatePoint($time);
    }
}

sub _calculatePoint {
    my ($this, $time) = @_;

    my $weightDB = $this->{'_db'}->{'weight'};
    my $emaDB = $this->{'_db'}->{'ema'};

    my $curValue = $weightDB->{$time};
    my $EMASoFar = 0;
    my $weightSoFar = 0;
    my $minTime;
    foreach my $key ( sort $NUM_SORT keys %{$weightDB} ) {
        # Only consider points up to and including the current point, obviously
        next if ( $key > $time );

        # first runthrough finds the min point
        $minTime ||= $key;

        my $value = $weightDB->{$key};
        my $delta = $time - $key;
        #print "Time Delta: " . ($delta / 60 / 60 / 24) . " days\n";
        my $weight = $this->_getDecayForDate($delta);
        $weightSoFar += $weight;
        $EMASoFar += $value * $weight;
    }

    my $ema = $EMASoFar / $weightSoFar;
#    print "DEBUG: Weight for ($time, $curValue) found to be $ema\n";
    $emaDB->{$time} = $ema;
}


# Weight at time differential t = initialWeight * e^(Q*t)
# Q = decay constant = -ln(2) / t(1/2)
# t(1/2) = half life
sub _getDecayForDate {
    my ($this, $age) = @_;

    my $q = log(2.0) / $this->{'halfLife'};
    my $decay = ( 1.0 * exp(-1.0 * $q * $age) );
#    print "DEBUG: Decay for age " . ($age/24/60/60) . " is $decay\n";
    return $decay;
}

sub _readDB {
    my ($this, $file) = @_;

    open(my $FH, '<', $file)
        or die "IOException: Unable to open '$file': $!\n";

    my $string;
    { local $\; $string = <$FH>; } 
    close($FH)
        or die "IOException: Unable to close '$file': $!\n";

    ($this->{'_db'})= thaw($string);
    # DB must store certain extra things for the data to make sense.
    $this->{'halfLife'} = $this->{'_db'}->{'halfLife'};
}

sub _writeDB {
    my ($this, $file) = @_;

    open(my $FH, '>', $file)
        or die "IOException: Unable to open '$file': $!\n";

    # DB must store certain extra things for the data to make sense.
    $this->{'_db'}->{'halfLife'} = $this->{'halfLife'};
    my $string = freeze($this->{'_db'});

    print $FH $string;

    close($FH)
        or die "IOException: Unable to close '$file': $!\n";
}

1;
