package Cmyers::Gnuplot;
use strict;
use vars qw($VERSION);
use Carp;
use File::Copy qw(move);
use File::Temp qw(tempdir);
use Chart::Gnuplot::Util qw(_lineType _pointType _copy);
$VERSION = '0.15';

# Constructor
sub new
{
    my ($class, %hash) = @_;

    # Create temporary file to store Gnuplot instructions
    if (!defined $hash{_multiplot})     # if not in multiplot mode
    {
        my $dirTmp = tempdir(CLEANUP => 1);
        ($^O eq 'MSWin32')? ($dirTmp .= '\\'): ($dirTmp .= '/');
        $hash{_script} = $dirTmp . "plot";
    }

    # Default terminal: postscript terminal with color drawing elements
    if (!defined $hash{terminal} && !defined $hash{term})
    {
        $hash{terminal} = "postscript enhanced color";
        $hash{_terminal} = 'auto';
    }

    # Default setting
    if (defined $hash{output})
    {
        my @a = split(/\./, $hash{output});
        my $ext = $a[-1];
        $hash{terminal} .= " eps" if ($hash{terminal} =~ /^post/ &&
            $ext eq 'eps');
    }

    my $self = \%hash;
    return bless($self, $class);
}


# Generic attribute methods
sub AUTOLOAD
{
    my ($self, $key) = @_;
    my $attr = our $AUTOLOAD;
    $attr =~ s/.*:://;
    return if ($attr eq 'DESTROY');        # ignore destructor
    $self->{$attr} = $key if (defined $key);
    return($self->{$attr});
}


# General set method
sub set
{
    my ($self, %opts) = @_;
    foreach my $opt (keys %opts)
    {
        ($opts{$opt} eq 'on')? $self->$opt('') : $self->$opt($opts{$opt});
    }
    return($self);
}


# Add a 2D data set to the chart object
# - used with multiplot
sub add2d
{
    my ($self, @dataSet) = @_;
    push(@{$self->{_dataSets2D}}, @dataSet);
}


# Add a 3D data set to the chart object
# - used with multiplot
sub add3d
{
    my ($self, @dataSet) = @_;
    push(@{$self->{_dataSets3D}}, @dataSet);
}


# Add a 2D data set to the chart object
# - redirect to &add2d
# - for backward compatibility
sub add {&add2d(@_);}


# Plot 2D graphs
# - call _setChart()
#
# TODO:
# - Consider using pipe instead of system call
# - support MS time format: %{yyyy}-%{mmm}-%{dd} %{HH}:%{MM}
sub plot2d
{
    my ($self, @dataSet) = @_;
    &_setChart($self, \@dataSet);

    my $plotString = join(', ', map {$_->_thaw($self)} @dataSet);
    open(GPH, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    print GPH "\nplot $plotString\n";
    close(GPH);

    # Generate image file
    &_execute($self);
    return($self);
}


# Plot 3D graphs
# - call _setChart()
#
# TODO:
# - Consider using pipe instead of system call
# - support MS time format: %{yyyy}-%{mmm}-%{dd} %{HH}:%{MM}
sub plot3d
{
    my ($self, @dataSet) = @_;
    &_setChart($self, \@dataSet);

    my $plotString = join(', ', map {$_->_thaw($self)} @dataSet);
    open(GPH, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    print GPH "\nsplot $plotString\n";
    close(GPH);

    # Generate image file
    &_execute($self);
    return($self);
}


# Plot multiple plots in one single chart
sub multiplot
{
    my ($self, @charts) = @_;
    &_setChart($self);
    &_reset($self);

    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");

    # Emulate the title when there is background color fill
    if (defined $self->{title} && defined $self->{bg})
    {
        print PLT "set label \"$self->{title}\" at screen 0.5, screen 1 ".
            "center offset 0,-1\n";
    }

    if (scalar(@charts) == 1 && ref($charts[0]) eq 'ARRAY')
    {
        my $nrows = scalar(@{$charts[0]});
        my $ncols = scalar(@{$charts[0][0]});
        &_setMultiplot($self, $nrows, $ncols);
    
        for (my $r = 0; $r < $nrows; $r++)
        {
            for (my $c = 0; $c < $ncols; $c++)
            {
                my $chart = $charts[0][$r][$c];
                $chart->_script($self->{_script});
                $chart->_multiplot(1);
                delete $chart->{bg};

                my $plot;
                my @dataSet;
                if (defined $chart->{_dataSets2D})
                {
                    $plot = 'plot';
                    @dataSet = @{$chart->{_dataSets2D}};
                }
                elsif (defined $chart->{_dataSets3D})
                {
                    $plot = 'splot';
                    @dataSet = @{$chart->{_dataSets3D}};
                }

                &_setChart($chart, \@dataSet);
                open(PLT, ">>$self->{_script}") ||
                    confess("Can't write $self->{_script}");
                print PLT "\n$plot ";
                print PLT join(', ', map {$_->_thaw($self)} @dataSet), "\n";
                close(PLT);
                &_reset($chart);
            }
        }
    }
    else
    {
        # Start multi-plot
        &_setMultiplot($self);

        foreach my $chart (@charts)
        {
            $chart->_script($self->{_script});
            $chart->_multiplot(1);
            delete $chart->{bg};

            my $plot;
            my @dataSet;
            if (defined $chart->{_dataSets2D})
            {
                $plot = 'plot';
                @dataSet = @{$chart->{_dataSets2D}};
            }
            elsif (defined $chart->{_dataSets3D})
            {
                $plot = 'splot';
                @dataSet = @{$chart->{_dataSets3D}};
            }
        
            &_setChart($chart, \@dataSet);
            open(PLT, ">>$self->{_script}") ||
                confess("Can't write $self->{_script}");
            print PLT "\n$plot ";
            print PLT join(', ', map {$_->_thaw($self)} @dataSet), "\n";
            close(PLT);
            &_reset($chart);
        }
    }
    close(PLT);

    # Generate image file
    &_execute($self);
    return($self);
}


# Pass generic commands
sub command
{
    my ($self, $cmd) = @_;

    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    print PLT "$cmd\n";
    close(PLT);
    return($self);
}


# Set how the chart looks like
# - call _setTitle(), _setAxisLabel(), _setTics(), _setGrid(), _setBorder(),
#        _setTimestamp()
# - called by plot2d() and plot3d()
sub _setChart
{
    my ($self, $dataSets) = @_;
    my @sets = ();

    # Orientation
    $self->{terminal} .= " $self->{orient}" if (defined $self->{orient});

    # Set canvas size
    if (defined $self->{imagesize})
    {
        my ($ws, $hs) = split(/,\s?/, $self->{imagesize});
        if (defined $self->{_terminal} && $self->{_terminal} eq 'auto')
        {
            # for post terminal
            if (defined $self->{orient} && $self->{orient} eq 'portrait')
            {
                $ws *= 7 if ($ws =~ /^([1-9]\d*)?0?(\.\d+)?$/);
                $hs *= 10 if ($hs =~ /^([1-9]\d*)?0?(\.\d+)?$/);
            }
            else
            {
                $ws *= 10 if ($ws =~ /^([1-9]\d*)?0?(\.\d+)?$/);
                $hs *= 7 if ($hs =~ /^([1-9]\d*)?0?(\.\d+)?$/);
            }
        }
        $self->{terminal} .= " size $ws,$hs";
    }

    # Prevent changing terminal in multiplot mode
    delete $self->{terminal} if (defined $self->{_multiplot});

    # Start writing gnuplot script
    my $pltTmp = $self->{_script};
    open(PLT, ">>$pltTmp") || confess("Can't write gnuplot script $pltTmp");

    # Set character encoding
    #
    # Quote from Gnuplot manual:
    # "Generally you must set the encoding before setting the terminal type."
    if (defined $self->{encoding})
    {
        print PLT "set encoding $self->{encoding}\n";
    }

    # Chart background color
    if (defined $self->{bg})
    {
        my $bg = $self->{bg};
        if (ref($bg) eq 'HASH')
        {
            print PLT "set object rect from screen 0, screen 0 to ".
                "screen 1, screen 1 fillcolor rgb \"$$bg{color}\"";
            print PLT " fillstyle solid $$bg{density}" if
                (defined $$bg{density});
            print PLT " behind\n";
        }
        else
        {
            print PLT "set object rect from screen 0, screen 0 to ".
                "screen 1, screen 1 fillcolor rgb \"$bg\" behind\n";
        }
        push(@sets, 'object');
    }

    # Plot area background color
    if (defined $self->{plotbg})
    {
        my $bg = $self->{plotbg};
        if (ref($bg) eq 'HASH')
        {
            print PLT "set object rect from graph 0, graph 0 to ".
                "graph 1, graph 1 fillcolor rgb \"$$bg{color}\"";
            print PLT " fillstyle solid $$bg{density}" if
                (defined $$bg{density});
            print PLT " behind\n";
        }
        else
        {
            print PLT "set object rect from graph 0, graph 0 to ".
                "graph 1, graph 1 fillcolor rgb \"$bg\" behind\n";
        }
        push(@sets, 'object');
    }

    # Set date/time data
    #
    # For xrange to work for time-sequence, time-axis ("set xdata time")
    # and timeformat ("set timefmt '%Y-%m-%d'") MUST be set BEFORE 
    # the range command ("set xrange ['2009-01-01','2009-01-07']")
    #
    # Thanks to Holyspell
    if (defined $self->{timeaxis})
    {
        my @axis = split(/,\s?/, $self->{timeaxis});
        foreach my $axis (@axis)
        {
            print PLT "set $axis"."data time\n";
            push(@sets, $axis."data");
        }

        foreach my $ds (@$dataSets)
        {
            if (defined $ds->{timefmt})
            {
                print PLT "set timefmt \"$ds->{timefmt}\"\n";
                last;
            }
        }
    }

    # Parametric plot
    foreach my $ds (@$dataSets)
    {
        # Determine if there is paramatric plot
        if (defined $ds->{func} && ref($ds->{func}) eq 'HASH')
        {
            $self->{parametric} = '';
            last;
        }
    }

    my $setGrid = 0;    # detect whether _setGrid has been run

    # Loop and process other chart options
    foreach my $attr (keys %$self)
    {
        if ($attr eq 'output')
        {
            print PLT "set output \"$self->{output}\"\n";
        }
        elsif ($attr eq 'title')
        {
            print PLT "set title ".&_setTitle($self->{title})."\n";
            push(@sets, 'title')
        }
        elsif ($attr =~ /^((x|y)2?|z)label$/)
        {
            print PLT "set $attr ".&_setAxisLabel($self->{$attr})."\n";
            push(@sets, $attr);
        }
        elsif ($attr =~ /^((x|y)2?|z|t|u|v)range$/)
        {
            if (ref($self->{$attr}) eq 'ARRAY')
            {
                # Deal with ranges from array reference
                if (defined $self->{timeaxis})
                {
                    print PLT "set $attr ['".join("':'", @{$self->{$attr}}).
                        "']\n";
                }
                else
                {
                    print PLT "set $attr [".join(":", @{$self->{$attr}})."]\n";
                }
            }
            elsif ($self->{$attr} eq 'reverse')
            {
                print PLT "set $attr [*:*] reverse\n";
            }
            else
            {
                print PLT "set $attr $self->{$attr}\n";
            }
            push(@sets, $attr);
        }
        elsif ($attr =~ /^(x|y|x2|y2|z)tics$/)
        {
            my ($axis) = ($attr =~ /^(.+)tics$/);
            print PLT "set $attr".&_setTics($self->{$attr})."\n";
            if (ref($self->{$attr}) eq 'HASH')
            {
                if (defined ${$self->{$attr}}{labelfmt})
                {
                    print PLT "set format $axis ".
                        "\"${$self->{$attr}}{labelfmt}\"\n";
                    push(@sets, 'format');
                }
                if (defined ${$self->{$attr}}{minor})
                {
                    my $nTics = ${$self->{$attr}}{minor}+1;
                    print PLT "set m$axis"."tics $nTics\n";
                    push(@sets, "m$axis"."tics");
                }
            }
            push(@sets, $attr);
        }
        elsif ($attr eq 'legend')
        {
            print PLT "set key".&_setLegend($self->{legend})."\n";
            push(@sets, 'key');
        }
        elsif ($attr eq 'border')
        {
            print PLT "set border".&_setBorder($self->{border})."\n";
            push(@sets, 'border');
        }
        elsif ($attr =~ /^(minor)?grid$/)
        {
            next if ($setGrid == 1);

            print PLT "set grid".&_setGrid($self)."\n";
            push(@sets, 'grid');
            $setGrid = 1;
        }
        elsif ($attr eq 'timestamp')
        {
            print PLT "set timestamp".&_setTimestamp($self->{timestamp})."\n";
            push(@sets, 'timestamp');
        }
        elsif ($attr eq 'terminal')
        {
            print PLT "set $attr $self->{$attr}\n";
        }
        elsif ($attr eq 'fillstyle') {
            print PLT "set style fill $self->{$attr}\n";
        }
        # Non-gnuplot options / options specially treated before
        elsif (!grep(/^$attr$/, qw(
                gnuplot
                convert
                encoding
                imagesize
                orient
                bg
                plotbg
                timeaxis
            )) &&
            $attr !~ /^_/)
        {
            (defined $self->{$attr} && $self->{$attr} ne '')?
                (print PLT "set $attr $self->{$attr}\n"):
                (print PLT "set $attr\n");
            push(@sets, $attr);
        }
    }

    # Write labels
    foreach my $label (@{$self->{_labels}})
    {
        print PLT "set label $label\n";
    }

    # Draw arrows
    foreach my $arrow (@{$self->{_arrows}})
    {
        print PLT "set arrow $arrow\n";
    }
    close(PLT);

    $self->_sets(\@sets);
}


# Set the details of the title
# - called by _setChart()
#
# Usage example:
# title => {
#     text   => "My title",
#     font   => "arial, 14",
#     color  => "brown",
#     offset => "0, -1",
# },
sub _setTitle
{
    my ($title) = @_;
    if (ref($title))
    {
        my $out = "\"$$title{text}\"";
        $out .= " offset $$title{offset}" if (defined $$title{offset});

        # Font and size
        my $font;
        $font = $$title{font} if (defined $$title{font});
        $font .= ",$$title{fontsize}" if (defined $$title{fontsize});
        $out .= " font \"$font\"" if (defined $font);

        # Color
        $out .= " textcolor rgb \"$$title{color}\"" if (defined $$title{color});

        # Switch of the enhanced mode. Default: off
        $out .= " noenhanced" if (!defined $$title{enhanced} ||
            $$title{enhanced} ne 'on');
        return($out);
    }
    else
    {
        return("\"$title\" noenhanced");
    }
}


# Set the details of the axis labels
# - called by _setChart()
#
# Usage example:
# xlabel => {
#     text   => "My x-axis label",
#     font   => "arial, 14",
#     color  => "brown",
#     offset => "0, -1",
#     rotate => 45,
# },
#
# TODO
# - support radian and pi in "rotate"
sub _setAxisLabel
{
    my ($label) = @_;
    if (ref($label))
    {
        my $out = "\"$$label{text}\"";

        # Location offset
        $out .= " offset $$label{offset}" if (defined $$label{offset});

        # Font and size
        my $font;
        $font = $$label{font} if (defined $$label{font});
        $font .= ",$$label{fontsize}" if (defined $$label{fontsize});
        $out .= " font \"$font\"" if (defined $font);

        # Color
        $out .= " textcolor rgb \"$$label{color}\"" if (defined $$label{color});

        # Switch of the enhanced mode. Default: off
        $out .= " noenhanced" if (!defined $$label{enhanced} ||
            $$label{enhanced} ne 'on');

        # Text rotation
        $out .= " rotate by $$label{rotate}" if (defined $$label{rotate});
        return($out);
    }
    else
    {
        return("\"$label\" noenhanced");
    }
}


# Set the details of the tics and tic labels
# - called by _setChart()
#
# Usage example:
# xtics => {
#    labels    => [-10, 15, 20, 25],
#    labelfmt  => "%3f",
#    font      => "arial",
#    fontsize  => 14,
#    fontcolor => "brown",
#    offset    => "0, -1",
#    rotate    => 45,
#    length    => "2,1",
#    along     => 'axis',
#    minor     => 3,
#    mirror    => 'off',
# },
#
# TODO
# - able to replace the label for specified text
# - implement "add" option to add addition tics other than default
# - support radian and pi in "rotate"
sub _setTics
{
    my ($tic) = @_;

    my $out = '';
    if (ref($tic) eq 'HASH')
    {
        $out .= " $$tic{along}" if (defined $$tic{along});
        $out .= " nomirror" if (
            defined $$tic{mirror} && $$tic{mirror} eq 'off'
        );
        $out .= " scale $$tic{length}" if (defined $$tic{length});
        $out .= " rotate by $$tic{rotate}" if (defined $$tic{rotate});
        $out .= " offset $$tic{offset}" if (defined $$tic{offset});
        $out .= " (". join(',', @{$$tic{labels}}) . ")" if
            (defined $$tic{labels});

        # Font, font size and font color
        if (defined $$tic{font})
        {
            my $font = $$tic{font};
            $font = "$$tic{font},$$tic{fontsize}" if ($font !~ /\,/ &&
                defined $$tic{fontsize});
            $out .= " font \"$font\"";
        }
        $out .= " textcolor rgb \"$$tic{fontcolor}\"" if
            (defined $$tic{fontcolor});
    }
    elsif (ref($tic) eq 'ARRAY')
    {
        $out = " (". join(',', @$tic) . ")";
    }
    elsif ($tic ne 'on')
    {
        $out = "\"$tic\"";
    }
    return($out);
}


# Set the details of the grid lines
# - called by _setChart()
#
# Usage example:
# grid => {
#     type    => 'dash, dot',        # default: dot
#     width   => 2,              # default: 0
#     color   => 'blue',         # default: black
#     xlines  => 'on',           # default: on
#     ylines  => 'off',          # default: on
#     zlines  => 'off',          # default:
#     x2lines => 'off',          # default: off
#     y2lines => 'off',          # default: off
# },
#
# minorgrid => {
#     width   => 1,              # default: 0
#     color   => 'gray',         # default: black
#     xlines  => 'on',           # default: off
#     ylines  => 'on',           # default: off
#     x2lines => 'off',          # default: off
#     y2lines => 'off',          # default: off
# }
#
# # OR
# 
# grid => 'on',
#
# TODO:
# - support polar grid
# - support layer <front/back>
sub _setGrid
{
    my ($self) = @_;
    my $grid = $self->{grid};
    my $mgrid = $self->{minorgrid} if (defined $self->{minorgrid});

    my $out = '';
    if (ref($grid) eq 'HASH' || ref($mgrid) eq 'HASH')
    {
        $grid = &_gridString2Hash($grid);
        $mgrid = &_gridString2Hash($mgrid);

        # Set whether the major grid lines are drawn
        (defined $$grid{xlines} && $$grid{xlines} =~ /^off/)?
            ($out .= " noxtics"): ($out .= " xtics");
        (defined $$grid{ylines} && $$grid{ylines} =~ /^off/)?
            ($out .= " noytics"): ($out .= " ytics");
        (defined $$grid{zlines} && $$grid{zlines} =~ /^off/)?
            ($out .= " noztics"): ($out .= " ztics");

        # Set whether the vertical minor grid lines are drawn
        $out .= " mxtics" if ( (defined $$grid{xlines} &&
            $$grid{xlines} =~ /,\s?on$/) ||
            (defined $self->{minorgrid} && (!defined $$mgrid{xlines} ||
            $$mgrid{xlines} eq 'on')) );

        # Set whether the horizontal minor grid lines are drawn
        $out .= " mytics" if ( (defined $$grid{ylines} &&
            $$grid{ylines} =~ /,\s?on$/) ||
            (defined $mgrid && (!defined $$mgrid{ylines} ||
            $$mgrid{ylines} eq 'on')) );

        # Major grid on secondary axes
        $out .= " x2tics" if (defined $$grid{x2lines} &&
            $$grid{x2lines} eq 'on');
        $out .= " y2tics" if (defined $$grid{y2lines} &&
            $$grid{y2lines} eq 'on');

        # Minor grid on secondary axes
        $out .= " mx2tics" if (defined $$mgrid{x2lines} &&
            $$mgrid{x2lines} eq 'on');
        $out .= " my2tics" if (defined $$mgrid{y2lines} &&
            $$mgrid{y2lines} eq 'on');

        # Set the line type of the grid lines
        my $major = my $minor = '';
        my $majorType = my $minorType = 4;  # dotted lines
        if (defined $$grid{linetype})
        {
            $majorType = $minorType = $$grid{linetype};
            ($majorType, $minorType) = split(/\,\s?/, $$grid{linetype}) if
                ($$grid{linetype} =~ /\,/);
        }
        $minorType = $$mgrid{linetype} if (defined $$mgrid{linetype});
        $major .= " linetype ".&_lineType($majorType);
        $minor .= " linetype ".&_lineType($minorType);
        
        # Set the line width of the grid lines
        my $majorWidth = my $minorWidth = 0;
        if (defined $$grid{width})
        {
            $majorWidth = $minorWidth = $$grid{width};
            ($majorWidth, $minorWidth) = split(/\,\s?/, $$grid{width}) if
                ($$grid{width} =~ /\,/);
        }
        $minorWidth = $$mgrid{width} if (defined $$mgrid{width});
        $major .= " linewidth $majorWidth";
        $minor .= " linewidth $minorWidth";

        # Set the line color of the grid lines
        my $majorColor = my $minorColor = 'black';
        if (defined $$grid{color})
        {
            $majorColor = $minorColor = $$grid{color};
            ($majorColor, $minorColor) = split(/\,\s?/, $$grid{color}) if
                ($$grid{color} =~ /\,/);
        }
        $minorColor = $$mgrid{color} if (defined $$mgrid{color});
        $major .= " linecolor rgb \"$majorColor\"";
        $minor .= " linecolor rgb \"$minorColor\"";
        $out .= "$major" if ($major ne '');
        $out .= ",$minor" if ($minor ne '');
    }
    else
    {
        if (defined $grid)
        {
            return($grid) if ($grid !~ /^(on|off)$/);
            ($grid eq 'off')? ($out = " noxtics noytics"):
                ($out = " xtics ytics");
        }
        $out .= " mxtics mytics" if (defined $mgrid && $mgrid eq 'on');
    }
    return($out);
}


# Convert grid string to hash
# - called by _setGrid
sub _gridString2Hash
{
    my ($grid) = @_;
    return($grid) if (ref($grid) eq 'HASH');

    my %out;
    $out{xlines} = $out{ylines} = $out{zlines} = $grid;
    return(\%out);
}


# Set the details of the graph border
# - called by _setChart()
#
# Usage example:
# border => {
#      linetype => 3,            # default: solid
#      width    => 2,            # default: 0
#      color    => '#ff00ff',    # default: system defined
# },
#
# Remark:
# - By default, the color of the axis tics would follow the border unless
#   specified otherwise.
#
# TODO:
# - support layer <front/back>
sub _setBorder
{
    my ($border) = @_;

    my $out = '';
    $out .= " linetype ".&_lineType($$border{linetype}) if
        (defined $$border{linetype});
    $out .= " linewidth $$border{width}" if (defined $$border{width});
    $out .= " linecolor rgb \"$$border{color}\"" if (defined $$border{color});
    return($out);
}


# Format the legend (key)
#
# Usage example:
# legend => {
#    position => "outside bottom",
#    width    => 3,
#    height   => 4,
#    align    => "right",
#    order    => "horizontal reverse",
#    title    => "Title of the legend",
#    sample   => {
#        length   => 3,
#        position => "left",
#        spacing  => 2,
#    },
#    border   => {
#        linetype => 2,
#        width    => 1,
#        color    => "blue",
#    },
# },
sub _setLegend
{
    my ($legend) = @_;

    my $out = '';
    if (defined $$legend{position})
    {
        ($$legend{position} =~ /\d/)? ($out .= " at $$legend{position}"):
            ($out .= " $$legend{position}");
    }
    $out .= " width $$legend{width}" if (defined $$legend{width});
    $out .= " height $$legend{height}" if (defined $$legend{height});
    if (defined $$legend{align})
    {
        $out .= " Left" if ($$legend{align} eq 'left');
        $out .= " Right" if ($$legend{align} eq 'right');
    }
    if (defined $$legend{order})
    {
        my $order = $$legend{order};
        $order =~ s/reverse/invert/;
        $out .= " $order";
    }
    if (defined $$legend{title})
    {
        if (ref($$legend{title}) eq 'HASH')
        {
            my $title = $$legend{title};
            $out .= " title \"$$title{text}\"";
            $out .= " noenhanced" if (!defined $$title{enhanced} ||
                $$title{enhanced} ne 'on');
        }
        else
        {
            $out .= " title \"$$legend{title}\" noenhanced";
        }
    }
    if (defined $$legend{sample})
    {
        $out .= " samplen $$legend{sample}{length}" if
            (defined $$legend{sample}{length});
        $out .= " reverse" if (defined $$legend{sample}{position} ||
            $$legend{sample}{position} eq "left");
        $out .= " spacing $$legend{sample}{spacing}" if
            (defined $$legend{sample}{spacing});
    }
    if (defined $$legend{border})
    {
        if (ref($$legend{border}) eq 'HASH')
        {
            $out .= " box ".&_setBorder($$legend{border});
        }
        elsif ($$legend{border} eq "off")
        {
            $out .= " no box";
        }
        elsif ($$legend{border} eq "on")
        {
            $out .= " box";
        }
    }
    return($out);
}


# Set title and layout of the multiplot
sub _setMultiplot
{
    my ($self, $nrows, $ncols) = @_;

    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    print PLT "set multiplot";
    print PLT " title \"$self->{title}\"" if (defined $self->{title});
    print PLT " layout $nrows, $ncols" if (defined $nrows);
    print PLT "\n";
    close(PLT);
}


# Usage example:
# timestamp => {
#    fmt    => '%d/%m/%y %H:%M',
#    offset => "10,-3"
#    font   => "Helvetica",
# },
# # OR
# timestamp => 'on';
sub _setTimestamp
{
    my ($ts) = @_;

    my $out = '';
    if (ref($ts) eq 'HASH')
    {
        $out .= " \"$$ts{fmt}\"" if (defined $$ts{fmt});
        $out .= " $$ts{offset}" if (defined $$ts{offset});
        $out .= " \"$$ts{font}\"" if (defined $$ts{font});
    }
    elsif ($ts ne 'on')
    {
        return($ts);
    }
    return($out);
}


# Generate the image file
sub _execute
{
    my ($self) = @_;

    # Execute gnuplot
    my $gnuplot = 'gnuplot';
    $gnuplot = $self->{gnuplot} if (defined $self->{gnuplot});
    my $cmd = "$gnuplot $self->{_script}";
    $cmd .= " -" if ($self->{terminal} =~ /^(ggi|pm|windows|wxt|x11)(\s|$)/);
#    my $err = `$cmd 2>&1`;
    my $err;
    system("$cmd");

    # Capture and process error message from Gnuplot
    if (defined $err && $err ne '')
    {
        my ($errTmp) = ($err =~ /\", line \d+:\s(.+)/);
        die "$errTmp\n" if (defined $errTmp);
        warn "$err\n";
    }

    # Convert the image to the user-specified format
    if (defined $self->{_terminal} && $self->{_terminal} eq 'auto')
    {
        my @a = split(/\./, $self->{output});
        my $ext = $a[-1];
        &convert($self, $ext) if ($ext !~ /^e?ps$/);
    }
}


# Unset the chart properties
# - called by multiplot()
sub _reset
{
    my ($self) = @_;
    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    foreach my $opt (@{$self->{_sets}})
    {
        print PLT "unset $opt\n";

        if ($opt =~ /range$/)
        {
            print PLT "set $opt [*:*]\n";
        }
        elsif (!grep(/^$opt$/, qw(grid object parametric)) && $opt !~ /tics$/)
        {
            print PLT "set $opt\n";
        }
    }
    close(PLT);
}


# Arbitrary labels placed in the chart
#
# Usage example:
# $chart->label(
#     text       => "This is a label",
#     position   => "0.2, 3 left",
#     offset     => "2,2",
#     rotate     => 45,
#     font       => "arial, 15",
#     fontcolor  => "dark-blue",
#     pointtype  => 3,
#     pointsize  => 5,
#     pointcolor => "blue",
# );
#
# TODO:
# - support layer <front/back>
sub label
{
    my ($self, %label) = @_;

    my $out = "\"$label{text}\"";
    $out .= " at $label{position}" if (defined $label{position});
    $out .= " offset $label{offset}" if (defined $label{offset});
    $out .= " rotate by $label{rotate}" if (defined $label{rotate});
    $out .= " font \"$label{font}\"" if (defined $label{font});
    $out .= " textcolor rgb \"$label{fontcolor}\"" if
        (defined $label{fontcolor});
    $out .= " noenhanced" if (!defined $label{enhanced} ||
        $label{enhanced} ne 'on');

    if (defined $label{pointtype} || defined $label{pointsize} ||
        defined $label{pointcolor})
    {
        $out .= " point";
        $out .= " pt ".&_pointType($label{pointtype}) if
            (defined $label{pointtype});
        $out .= " ps $label{pointsize}" if (defined $label{pointsize});
        $out .= " lc rgb \"$label{pointcolor}\"" if
            (defined $label{pointcolor});
    }

    push(@{$self->{_labels}}, $out);
    return($self);
}


# Arbitrary arrows placed in the chart
#
# Usage example:
# $chart->arrow(
#     from      => "0,2",
#     to        => "0.3,0.1",
#     linetype  => 'dash',
#     width     => 2,
#     color     => "dark-blue",
#     headsize  => 3,
#     head      => 'both',
# );
sub arrow
{
    my ($self, %arrow) = @_;
    confess("Starting position of arrow not found") if (!defined $arrow{from});

    my $out = '';
    $out .= " from $arrow{from}";
    $out .= " to $arrow{to}" if (defined $arrow{to});
    $out .= " rto $arrow{rto}" if (defined $arrow{rto});
    $out .= " linetype ".&_lineType($arrow{linetype}) if
        (defined $arrow{linetype});
    $out .= " linewidth $arrow{width}" if (defined $arrow{width});
    $out .= " linecolor rgb \"$arrow{color}\"" if (defined $arrow{color});
    $out .= " size $arrow{headsize}" if (defined $arrow{headsize});

    if (defined $arrow{head})
    {
        if ($arrow{head} eq 'off')
        {
            $out .= " nohead";
        }
        elsif ($arrow{head} eq 'back')
        {
            $out .= " backhead";
        }
        elsif ($arrow{head} eq 'both')
        {
            $out .= " heads";
        }
    }

    push(@{$self->{_arrows}}, $out);
    return($self);
}


# Output a test image for the terminal
#
# Usage example:
# $chart = Chart::Gnuplot->new(output => "test.png");
# $chart->test;
sub test
{
    my ($self) = @_;

    my $pltTmp = "$self->{_script}";
    open(PLT, ">$pltTmp") || confess("Can't write gnuplot script $pltTmp");
    print PLT "set terminal $self->{terminal}\n";
    print PLT "set output \"$self->{output}\"\n";
    print PLT "test\n";
    close(PLT);

    # Execute gnuplot
    my $gnuplot = 'gnuplot';
    $gnuplot = $self->{gnuplot} if (defined $self->{gnuplot});
    system("$gnuplot $pltTmp");
    return($self);
}


# Change the image format
# - called by plot2d()
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data);
# $chart->convert('gif');
sub convert
{
    my ($self, $imgfmt) = @_;
    return($self) if (!-e $self->{output});

    # Generate temp file
    my $temp = "$self->{_script}.tmp";
    move($self->{output}, $temp);

    # Execute gnuplot
    my $convert = 'convert';
    $convert = $self->{convert} if (defined $self->{convert});

    # Rotate 90 deg for landscape image
    if (defined $self->{orient} && $self->{orient} eq 'portrait')
    {
        my $cmd = "$convert $temp $temp".".$imgfmt 2>&1";
        my $err = `$cmd`;
        if (defined $err && $err ne '')
        {
            die "Unsupported image format ($imgfmt)\n" if
                ($err =~ /^convert: unable to open module file/);

            my ($errTmp) = ($err =~ /^convert: (.+)/);
            die "$errTmp Perhaps the image format is not supported\n" if
                (defined $errTmp);
            die "$err\n";
        }
    }
    else
    {
        my $cmd = "$convert -rotate 90 $temp $temp".".$imgfmt 2>&1";
        my $err = `$cmd`;
        if (defined $err && $err ne '')
        {
            die "Unsupported image format ($imgfmt)\n" if
                ($err =~ /^convert: unable to open module file/);

            my ($errTmp) = ($err =~ /^convert: (.+)/);
            die "$errTmp Perhaps the image format is not supported\n" if
                (defined $errTmp);
            die "$err\n";
        }
    }

    # Remove the temp file
    move("$temp".".$imgfmt", $self->{output});
    unlink($temp);
    return($self);
}


# Change the image format to PNG
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->png;
sub png
{
    my $self = shift;
    &convert($self, 'png');
    return($self)
}


# Change the image format to GIF
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->gif;
sub gif
{
    my $self = shift;
    &convert($self, 'gif');
    return($self)
}


# Change the image format to JPG
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->jpg;
sub jpg
{
    my $self = shift;
    &convert($self, 'jpg');
    return($self)
}


# Change the image format to PS
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->ps;
sub ps
{
    my $self = shift;
    &convert($self, 'ps');
    return($self)
}


# Change the image format to PDF
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->pdf;
sub pdf
{
    my $self = shift;
    &convert($self, 'pdf');
    return($self)
}


# Copy method of the chart object
sub copy
{
    my ($self, $num) = @_;
    my @clone = &_copy(@_);

    foreach my $clone (@clone)
    {
        my $dirTmp = tempdir(CLEANUP => 1);
        ($^O eq 'MSWin32')? ($dirTmp .= '\\'): ($dirTmp .= '/');
        $clone->{_script} = $dirTmp . "plot";
    }
    return($clone[0]) if (!defined $num);
    return(@clone);
}

################## Chart::Gnuplot::DataSet class ##################

package Chart::Gnuplot::DataSet;
use strict;
use Carp;
use File::Temp qw(tempdir);
use Chart::Gnuplot::Util qw(_lineType _pointType _copy);

# Constructor
sub new
{
    my ($class, %hash) = @_;

    my $dirTmp = tempdir(CLEANUP => 1);
    ($^O eq 'MSWin32')? ($dirTmp .= '\\'): ($dirTmp .= '/');
    $hash{_data} = $dirTmp . "data";

    my $self = \%hash;
    return bless($self, $class);
}


# Generic attribute methods
sub AUTOLOAD
{
    my ($self, $key) = @_;
    my $attr = our $AUTOLOAD;
    $attr =~ s/.*:://;
    return if ($attr eq 'DESTROY');        # ignore destructor
    $self->{$attr} = $key if (defined $key);
    return($self->{$attr});
}


# xdata get-set method
sub xdata
{
    my ($self, $xdata) = @_;
    return($self->{xdata}) if (!defined $xdata);

    delete $self->{points};
    delete $self->{datafile};
    delete $self->{func};
    $self->{xdata} = $xdata;
}


# ydata get-set method
sub ydata
{
    my ($self, $ydata) = @_;
    return($self->{ydata}) if (!defined $ydata);

    delete $self->{points};
    delete $self->{datafile};
    delete $self->{func};
    $self->{ydata} = $ydata;
}


# zdata get-set method
sub zdata
{
    my ($self, $zdata) = @_;
    return($self->{zdata}) if (!defined $zdata);

    delete $self->{points};
    delete $self->{datafile};
    delete $self->{func};
    $self->{zdata} = $zdata;
}


# points get-set method
sub points
{
    my ($self, $points) = @_;
    return($self->{points}) if (!defined $points);

    delete $self->{xdata};
    delete $self->{ydata};
    delete $self->{zdata};
    delete $self->{datafile};
    delete $self->{func};
    $self->{points} = $points;
}


# datafile get-set method
sub datafile
{
    my ($self, $datafile) = @_;
    return($self->{datafile}) if (!defined $datafile);

    delete $self->{xdata};
    delete $self->{ydata};
    delete $self->{zdata};
    delete $self->{points};
    delete $self->{func};
    $self->{datafile} = $datafile;
}


# func get-set method
sub func
{
    my ($self, $func) = @_;
    return($self->{func}) if (!defined $func);

    delete $self->{xdata};
    delete $self->{ydata};
    delete $self->{zdata};
    delete $self->{points};
    delete $self->{datafile};
    $self->{func} = $func;
}



# Thaw the data set object to string
# - call _fillStyle()
#
# TODO:
# - data file delimiter
# - data labels
# - zdata
sub _thaw
{
    my ($self, $chart) = @_;
    my $string;
    my $using = '';

    # Data points stored in arrays
    # - in any case, ydata need to be defined
    if (defined $self->{ydata})
    {
        my $ydata = $self->{ydata};
        my $fileTmp = $self->{_data};
        open(DATA, ">$fileTmp") || confess("Can't write data to temp file");

        # Process 3D data set
        # - zdata is defined
        if (defined $self->{zdata})
        {
            my $zdata = $self->{zdata};
            my $xdata = $self->{xdata};
            croak("x-data and y-data have unequal length") if
                (scalar(@$ydata) ne scalar(@$xdata));
            croak("y-data and z-data have unequal length") if
                (scalar(@$ydata) ne scalar(@$zdata));
            for (my $i = 0; $i < @$xdata; $i++)
            {
                print DATA "\n" if ($i > 0 && $$xdata[$i] != $$xdata[$i-1]);
                print DATA "$$xdata[$i] $$ydata[$i] $$zdata[$i]\n";
            }
            $string = "'$fileTmp'";

            # Construst using statement for date-time data
            if (defined $self->{timefmt})
            {
                my @a = split(/\s+/, $$xdata[0]);
                my $yCol = scalar(@a) + 1;
                $using = "1:$yCol";

                my @b = split(/\s+/, $$ydata[0]);
                my $zCol = scalar(@b) + $yCol;
                $using .= ":$zCol";
            }
        }
        # Treatment for financebars and candlesticks styles
        # - Both xdata and ydata are defined
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} =~ /^(financebars|candlesticks)$/)
        {
            my $xdata = $self->{xdata};
            croak("x-data and y-data have unequal length") if
                (scalar(@{$$ydata[0]}) ne scalar(@$xdata));

            for (my $i = 0; $i < @$xdata; $i++)
            {
                print DATA "$$xdata[$i] $$ydata[0][$i] $$ydata[1][$i] ".
                    "$$ydata[2][$i] $$ydata[3][$i]\n";
            }
            $string = "'$fileTmp'";

            # Construst using statement for date-time data
            if (defined $self->{timefmt})
            {
                my @a = split(/\s+/, $$xdata[0]);
                my $yCol = scalar(@a) + 1;
                $using = "1:".join(':', ($yCol .. $yCol+3));
            }
        }
        # Treatment for errorbars and errorlines styles
        # - Both xdata and ydata are defined
        # - Style is defined and contain "error"
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} =~ /error/)
        {
            my $xdata = $self->{xdata};

            # Error bars along x-axis
            if ($self->{style} =~ /^xerror/)
            {
                croak("x-data and y-data have unequal length") if
                    (scalar(@{$$xdata[0]}) ne scalar(@$ydata));

                for (my $i = 0; $i < @$ydata; $i++)
                {
                    print DATA "$$xdata[0][$i] $$ydata[$i]";
                    for(my $j = 1; $j < @$xdata; $j++)
                    {
                        print DATA " $$xdata[$j][$i]";
                    }
                    print DATA "\n";
                }
            }
            # Error bars along y-axis
            elsif ($self->{style} =~ /^(y|box)error/)
            {
                croak("x-data and y-data have unequal length") if
                    (scalar(@{$$ydata[0]}) ne scalar(@$xdata));

                for (my $i = 0; $i < @$xdata; $i++)
                {
                    print DATA "$$xdata[$i] $$ydata[0][$i]";
                    for(my $j = 1; $j < @$ydata; $j++)
                    {
                        print DATA " $$ydata[$j][$i]";
                    }
                    print DATA "\n";
                }
            }
            # Error bars along both x and y-axis
            elsif ($self->{style} =~ /^(box)?xyerror/)
            {
                if (scalar(@$xdata) == scalar(@$ydata))
                {
                    for (my $i = 0; $i < @{$$xdata[0]}; $i++)
                    {
                        print DATA "$$xdata[0][$i] $$ydata[0][$i]";
                        for(my $j = 1; $j < @$ydata; $j++)
                        {
                            print DATA " $$xdata[$j][$i] $$ydata[$j][$i]";
                        }
                        print DATA "\n";
                    }
                }
                else
                {
                    for (my $i = 0; $i < @{$$xdata[0]}; $i++)
                    {
                        print DATA "$$xdata[0][$i] $$ydata[0][$i]";
                        if (scalar(@$xdata) == 2)
                        {
                            my $ltmp = $$xdata[0][$i] - $$xdata[1][$i]*0.5;
                            my $htmp = $$xdata[0][$i] + $$xdata[1][$i]*0.5;
                            print DATA " $ltmp $htmp ".
                                "$$ydata[1][$i] $$ydata[2][$i]\n";
                        }
                        else
                        {
                            my $ltmp = $$ydata[0][$i] - $$ydata[1][$i]*0.5;
                            my $htmp = $$ydata[0][$i] - $$ydata[1][$i]*0.5;
                            print DATA " $$xdata[1][$i] $$xdata[2][$i] ".
                                "$ltmp $htmp\n";
                        }
                    }
                }
            }
            $string = "'$fileTmp'";
            
            # Construst using statement for date-time data
            if (defined $self->{timefmt})
            {
                my ($xTmp) = (ref($$xdata[0]) eq 'ARRAY')? ($$xdata[0][0]):
                    ($$xdata[0]);
                my @a = split(/\s+/, $xTmp);
                my $yCol = scalar(@a) + 1;
                $using = "1:$yCol";
            }
        }
        # Treatment for hbars
        # - use "boxxyerrorbars" style to mimic
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} eq 'hbars')
        {
            my $xdata = $self->{xdata};
            my $ylow = my $yhigh = $$ydata[0];
            if (scalar(@$ydata) > 1)
            {
                $ylow = 0.5*(3*$$ydata[0]-$$ydata[1]);
                $yhigh = 0.5*(3*$$ydata[-1]-$$ydata[-2]);
            }

            for (my $i = 0; $i < @$xdata; $i++)
            {
                $ylow = 0.5*($$ydata[$i]+$$ydata[$i-1]) if ($i > 0);
                $yhigh = 0.5*($$ydata[$i]+$$ydata[$i+1]) if ($i < $#$ydata);
                print DATA "0 $$ydata[$i] 0 $$xdata[$i] $ylow $yhigh\n";
            }
            $self->{style} = "boxxyerrorbars";
            $string = "'$fileTmp'";
        }
        # Treatment for hlines
        # - use "boxxyerrorbars" style to mimic
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} eq 'hlines')
        {
            my $xdata = $self->{xdata};
            for (my $i = 0; $i < @$xdata; $i++)
            {
                print DATA "0 $$ydata[$i] 0 $$xdata[$i] $$ydata[$i] ".
                    "$$ydata[$i]\n";
            }
            $self->{style} = "boxxyerrorbars";
            $string = "'$fileTmp'";
        }
        # Normal x-y plot
        # - Both xdata and ydata are defined
        elsif (defined $self->{xdata})
        {
            my $xdata = $self->{xdata};
            croak("x-data and y-data have unequal length") if
                (scalar(@$ydata) ne scalar(@$xdata));
            for (my $i = 0; $i < @$xdata; $i++)
            {
                print DATA "$$xdata[$i] $$ydata[$i]\n";
            }
            $string = "'$fileTmp'";

            # Construst using statement for date-time data
            if (defined $self->{timefmt})
            {
                my @a = split(/\s+/, $$xdata[0]);
                my $yCol = scalar(@a) + 1;
                $using = "1:$yCol";
            }
        }
        # Only ydata is defined
        else
        {
            # Treatment for financebars and candlesticks styles
            if (defined $self->{style} &&
                $self->{style} =~ /^(financebars|candlesticks)$/)
            {
                for (my $i = 0; $i < @{$$ydata[0]}; $i++)
                {
                    print DATA "$i $$ydata[0][$i] $$ydata[1][$i] ".
                        "$$ydata[2][$i] $$ydata[3][$i]\n";
                }
            }
            # Treatment for errorbars and errorlines styles
            # - Style is defined and contain "error"
            elsif (defined $self->{style} && $self->{style} =~ /^yerror/)
            {
                for (my $i = 0; $i < @{$$ydata[0]}; $i++)
                {
                    print DATA "$i $$ydata[0][$i]";
                    for(my $j = 1; $j < @$ydata; $j++)
                    {
                        print DATA " $$ydata[$j][$i]";
                    }
                    print DATA "\n";
                }
            }
            # ydata vs index
            else
            {
                for (my $i = 0; $i < @$ydata; $i++)
                {
                    print DATA "$i $$ydata[$i]\n";
                }
            }
            $string = "'$fileTmp'";
            if (defined $self->{timefmt})
            {
                $using = "1:2";
            }
        }

        close(DATA);
    }
    # Data in points
    elsif (defined $self->{points})
    {
        my $pt = $self->{points};
        my $fileTmp = $self->{_data};
        open(DATA, ">$fileTmp") || confess("Can't write data to temp file");

        # 2D data points
        if (scalar(@{$$pt[0]}) == 2 ||
            (defined $self->{style} && $self->{style} =~ /error/))
        {
            # hlines plotting style
            if (defined $self->{style} && $self->{style} eq 'hlines')
            {
                for(my $i = 0; $i < @$pt; $i++)
                {
                    print DATA "0 $$pt[$i][1] 0 $$pt[$i][0] $$pt[$i][1] ".
                        "$$pt[$i][1]\n";
                }
                $self->{style} = "boxxyerrorbars";
            }
            # hbars plotting style
            elsif (defined $self->{style} && $self->{style} eq 'hbars')
            {
                my $ylow = my $yhigh = $$pt[0][1];
                if (scalar(@$pt) > 1)
                {
                    $ylow = 0.5*(3*$$pt[0][1]-$$pt[1][1]);
                    $yhigh = 0.5*(3*$$pt[-1][1]-$$pt[-2][1]);
                }

                for(my $i = 0; $i < @$pt; $i++)
                {
                    $ylow = 0.5*($$pt[$i][1]+$$pt[$i-1][1]) if ($i > 0);
                    $yhigh = 0.5*($$pt[$i][1]+$$pt[$i+1][1]) if ($i < $#$pt);
                    print DATA "0 $$pt[$i][1] 0 $$pt[$i][0] $ylow $yhigh\n";
                }
                $self->{style} = "boxxyerrorbars";
            }
            else
            {
                for(my $i = 0; $i < @$pt; $i++)
                {
                    print DATA join(" ", @{$$pt[$i]}), "\n";
                }
            }
        }
        # 3D data points
        elsif (scalar(@{$$pt[0]}) == 3)
        {
            my $xLast;
            for(my $i = 0; $i < @$pt; $i++)
            {
                print DATA join(" ", @{$$pt[$i]}), "\n";
                print DATA "\n" if (defined $xLast && $$pt[$i][0] != $xLast);
                $xLast = $$pt[$i][0];
            }
        }
        else
        {
            for(my $i = 0; $i < @$pt; $i++)
            {
                print DATA join(" ", @{$$pt[$i]}), "\n";
            }
        }
        close(DATA);
        $string = "'$fileTmp'";

        # Construst using statement for date-time data
        if (defined $self->{timefmt})
        {
            my $col = 1;
            $using = "1";
            for (my $i = 0; $i < @{$$pt[0]}-1; $i++)
            {
                my @a = split(/\s+/, $$pt[0][$i]);
                $col += scalar(@a);
                $using .= ":$col";
            }
        }
    }
    # File
    elsif (defined $self->{datafile})
    {
        $string = "'$self->{datafile}'";
        $string .= " every $self->{every}" if (defined $self->{every});
        $string .= " index $self->{index}" if (defined $self->{index});
    }
    # Function
    elsif (defined $self->{func})
    {
        # Parametric function
        if (ref($self->{func}) eq 'HASH')
        {
            if (defined ${$self->{func}}{z})
            {
                $string = "${$self->{func}}{x},${$self->{func}}{y},".
                    "${$self->{func}}{z}";
            }
            else
            {
                $string = "${$self->{func}}{x},${$self->{func}}{y}";
            }
        }
        else
        {
            $string = "$self->{func}";
        }
    }
	else
	{
		croak("Unknown or undefined data source");
	}

    # Process the Gnuplot "using" feature
    $using = $self->{using} if (defined $self->{using});
    $string .= " using $using" if ($using ne '');

    # Add title for the data sets
    (defined $self->{title})? ($string .= " title \"$self->{title}\""):
        ($string .= " title \"\"");

    # Change plotting style, color, width and point size
    $string .= " smooth $self->{smooth}" if (defined $self->{smooth});
    $string .= " axes $self->{axes}" if (defined $self->{axes});
    $string .= " with $self->{style}" if (defined $self->{style});
    $string .= " linetype ".&_lineType($self->{linetype}) if
        (defined $self->{linetype});
    $string .= " linecolor rgb \"$self->{color}\"" if (defined $self->{color});
    $string .= " linewidth $self->{width}" if (defined $self->{width});
    $string .= " pointtype ".&_pointType($self->{pointtype}) if
        (defined $self->{pointtype});
    $string .= " pointsize $self->{pointsize}" if (defined $self->{pointsize});
    $string .= " fill".&_fillStyle($self->{fill}) if (defined $self->{fill});
    return($string);
}


# Generate box filling style string
# - called by _thaw()
sub _fillStyle
{
    my ($fill) = @_;

    if (ref($fill) eq 'HASH')
    {
        my $style = " solid $$fill{density}";
        $style .= " noborder" if (defined $$fill{border} &&
            $$fill{border} =~ /^(off|no)$/);
        return($style);
    }

    return(" solid $fill");
}


# Copy method of the data set object
sub copy
{
    my ($self, $num) = @_;
    my @clone = &_copy(@_);

    foreach my $clone (@clone)
    {
        my $dirTmp = tempdir(CLEANUP => 1);
        ($^O eq 'MSWin32')? ($dirTmp .= '\\'): ($dirTmp .= '/');
        $clone->{_data} = $dirTmp . "data";
    }
    return($clone[0]) if (!defined $num);
    return(@clone);
}


1;

__END__

=head1 NAME

Chart::Gnuplot - Plot graph using Gnuplot on the fly

=head1 SYNOPSIS

    use Chart::Gnuplot;
    
    # Data
    my @x = (-10 .. 10);
    my @y = (0 .. 20);
    
    # Create chart object and specify the properties of the chart
    my $chart = Chart::Gnuplot->new(
        output => "fig/simple.png",
        title  => "Simple testing",
        xlabel => "My x-axis label",
        ylabel => "My y-axis label",
        ....
    );
    
    # Create dataset object and specify the properties of the dataset
    my $dataSet = Chart::Gnuplot::DataSet->new(
        xdata => \@x,
        ydata => \@y,
        title => "Plotting a line from Perl arrays",
        style => "linespoints",
        ....
    );
    
    # Plot the data set on the chart
    $chart->plot2d($dataSet);
    
    ##################################################
    
    # Plot many data sets on a single chart
    $chart->plot2d($dataSet1, $dataSet2, ...);

=head1 DESCRIPTION

This module is to plot graphs uning GNUPLOT on the fly. In order to use this
module, gnuplot need to be installed. If image format other than PS and EPS is
required to generate, the convert program of ImageMagick is also needed.

To plot chart using Chart::Gnuplot, a chart object and at least one dataset
object are required. Information about the chart such as output file, chart
title, axes labels and so on is specified in the chart object.  Dataset object
contains information about the dataset to be plotted, including source of the
data points, dataset label, color used to plot and more.

After chart object and dataset object(s) are created, the chart can be plotted
using the plot2d, plot3d or multiplot method of the chart object, e.g.

    # $chart is the chart object
    $chart->plot2d($dataSet1, $dataSet2, ...);

To illustate the features of Chart::Gnuplot, the best way is to show by
examples. A lot of examples are provided in the package.

=head1 CHART OBJECT

The chart object can be initiated by the c<new> method. Properties of the chart
may be specified optionally when the object is initiated:

    my $chart = Chart::Gnuplot->new(%options);

=head2 Chart Options

=head3 output

Output file of the graph. By default, the image format is detected
automatically by the extension of the filename. However, it can also be changed
manually by using the format conversion methods such as C<convert> and C<png>
(see sessions below).

The supported image formats are:

    bmp  : Microsoft Windows bitmap
    epdf : Encapsulated Portable Document Format
    epi  : Encapsulated PostScript Interchange format
    eps  : Encapsulated PostScript
    gif  : Graphics Interchange Format
    jpg  : Joint Photographic Experts Group JFIF format
    pdf  : Portable Document Format
    png  : Portable Network Graphics
    ppm  : Portable Pixmap Format
    ps   : PostScript file
    psd  : Adobe Photoshop bitmap file
    xpm  : X Windows system pixmap

If the filename has no extension, postscipt will be used.

=head3 title

Title of the chart. E.g.,

    title => "Chart title"

Properties of the chart title can be specified in hash. E.g.,

    title => {
        text => "Chart title",
        font => "arial, 20",
        ....
    }

Supported properties are:

    text     : title in plain text
    font     : font face (and optionally font size)
    color    : font color
    offset   : offset relative to the default position
    enhanced : title contains subscript/superscipt/greek? (on/off)

Default values would be used for properties not specified. These properties has
no effect on the main title of the multi-chart (see L<multiplot>).

=head3 xlabel, ylabel, zlabel

Label of the x-axis, y-axis and z-axis. E.g.

    xlabel => "Bottom axis label"

Properties of the axis label can be specified in hash, similar to the chart
title. Supported properties are:

    text     : title in plain text
    font     : font face (and optionally font size)
    color    : font color
    offset   : offset relative to the default position
    rotate   : rotation in degrees
    enhanced : title contains subscript/superscipt/greek? (on/off)

=head3 x2label, y2label

Label of the secondary x-axis (displayed on the top of the graph) and the
secondary y-axis (displayed on the right of the graph). See L<xlabel>.

=head3 xrange, yrange, zrange

Range of the x-axis, y-axis and z-axis in the plot, e.g.

    xrange => [0, "pi"]

=head3 x2range, y2range

Range of the secondary axes in the plot. See L<xrange>.

=head3 trange, urange, vrange

Range of the parametric parameter (t for 2D plots, while u and v for 3D plots).
See L<xrange>.

=head3 xtics, ytics, ztics

The tics and tic label on the x-axis, y-axis and z-axis. E.g.

   xtics => {
      labels   => [-10, 15, 20, 25],
      labelfmt => "%3f",
      ....
   }

Supported properties are:

    labels    : the locations of the tic labels
    labelfmt  : format of the labels
    font      : font of the labels
    fontsize  : font size of the lebals
    fontcolor : font color of the label
    offset    : position of the tic labels shifted from its default
    rotate    : rotation of the tic labels
    length    : length of the tics
    along     : where the tics are put (axis/border)
    minor     : number of minor tics between adjacant major tics
    mirror    : turn on and off the tic label of the secondary axis. No effect
              : for C<ztics> (on/off)

=head3 x2tics, y2tics

The tics and tic label of the secondary axes. See L<xtics, ytics, ztics>.

=head3 legend

Legend describing the plots. Supported properties are:

    position : position of the legend
    width    : number of character widths to be added or subtracted to the
             : region of the legend
    height   : number of character heights to be added or subtracted to the
             : region of the legend
    align    : alignment of the text label. Left or right (default)
    order    : order of the keys
    title    : title of the legend
    sample   : format of the sample lines
    border   : border of the legend
    
See L<border> for the available options of border

E.g.

    legend => {
       position => "outside bottom",
       width    => 3,
       height   => 4,
       align    => "right",
       order    => "horizontal reverse",
       title    => "Title of the legend",
       sample   => {
           length   => 3,
           position => "left",
           spacing  => 2,
       },
       border   => {
           linetype => 2,
           width    => 1,
           color    => "blue",
       },
    }

=head3 timeaxis

Specify the axes of which the tic labels are date/time string. Possible values
are combinations of "x", "y", "x2", and "y2" joined by ",". E.g.

    timeaxis => "x, y2"

means that the x-axis and y2-axis are data/time axes.

=head3 border

Border of the graph. Properties supported are "linetype", "width", and "color".
E.g.

    border => {
        linetype => 3,
        width    => 2,
        color    => '#ff00ff',
    }

=head3 grid

Major grid lines. E.g.

    grid => {
        type  => 'dash',
        width => 2,
        ....
    }

Supported properties are:

    type   : line type of the grid lines (default: dot)
    width  : line width (defaulr: 0)
    color  : line color (default: black)
    xlines : whether the vertical grid lines are drawn (on/off)
    ylines : whether the horizontal grid lines are drawn (on/off)

=head3 tmargin, bmargin

Top and bottom margin (in character height). This option has no effect in 3D
plots. E.g.

    tmargin => 10

=head3 lmargin, rmargin

Left amd right margin (in character width). This option has no effect in 3D
plots. See L<tmargin, bmargin>.

=head3 orient

Orientation of the image. Possible values are "lanscape" (default) and
"portrait". E.g.

    orient => "portrait"

=head3 imagesize

Size (length and height) of the image relative to the default. E.g.

    imagesize => "0.8, 0.5"

=head3 size

Size of the plot relative to the chart size. This is useful in some
multi-plot such as inset chart. E.g.

    size => "0.5, 0.4"

=head3 origin

Origin of the chart. This is useful in some multi-plot such as inset chart.
E.g.

    origin => "0.1, 0.5"

=head3 timestamp

Time stamp of the plot. To place the time stamp with default setting,

    timestamp => 'on'

To set the format of the time stamp as well, e.g.,

    timestamp => {
       fmt    => '%d/%m/%y %H:%M',
       offset => "10,-3",
       font   => "Helvetica",
    }

=head3 bg (experimental)

Background color of the chart. This option has no effect in the sub-chart of
multiplot and is experimental. E.g.

    bg => "yellow"

Properties can be specified in hash. E.g.,

    bg => {
        color   => "yellow",
        density => 0.2,
    }

Supported properties are:

    color   : color (name ot RRGGBB value)
    density : density of the coloring

=head3 plotbg (experimental)

Background color of the plot area. This option has no effect in 3D plots and is
experimental. See L<bg>.

=head3 gnuplot

The path of Gnuplot executable. This option is useful if you are using Windows
or have multiple versions of Gnuplot installed. E.g.,

    gnuplot => "C:\Program Files\...\gnuplot\bin\wgnuplot.exe";   # for Windows

=head3 convert

The path of convert executable of ImageMagick. This option is useful if you
have multiple convert executables.

=head3 terminal

The terminal driver that Gnuplot uses. The default terminal is "postscript".
This attribute is not recommended to be changed unless you are familiar with
the Gnuplot syntax. Please check the output image carefully if you use this in
production code.

Terminal is not necessarily related to the output image format. You may convert
the image format by the C<convert()> method.

=head2 Chart Methods

=head3 new

    my $chart = Chart::Gnuplot->new(%options);

Constructor of the chart object. If no option is specified, default values
would be used. See L<Chart Options> for available options.

=head3 set

General set methods for arbitrary number of options.

    $chart->set(%options);

=head3 plot2d

    $chart->plot2d(@dataSets);

Plot the data sets in a 2D chart. Each dataset is represented by a dataset
object.

=head3 plot3d

    $chert->plot3d(@dataSets);

Plot the data sets in a 3D chart. Each dataset is represented by a dataset
object. It is not yet completed. Only basic features are supported.

=head3 multiplot

    $chert->multiplot(@charts);

Plot multiple charts in the same image.

=head3 add2d

Add a 2D dataset to a chart without plotting it out immediately. Used with
C<multiplot>.

=head3 add3d

Add a 3D dataset to a chart without plotting it out immediately. Used with
C<multiplot>.

=head3 label

Add an arbitrary text label. e.g.,

    $chart->label(
        text       => "This is a label",
        position   => "0.2, 3 left",
        offset     => "2,2",
        rotate     => 45,
        font       => "arial, 15",
        fontcolor  => "dark-blue",
        pointtype  => 3,
        pointsize  => 5,
        pointcolor => "blue",
    );

=head3 arrow

Draw arbitrary arrow. e.g.,

    $chart->arrow(
        from      => "0,2",
        to        => "0.3,0.1",
        linetype  => 'dash',
        width     => 2,
        color     => "dark-blue",
        headsize  => 3,
        head      => 'both',
    );

=head3 copy

Copy the chart object. This method is especially useful when you want to copy a
chart with highly customized format. E.g.

    my $chart = Chart::Gnuplot->new(
        ...
    );

    # $copy and $chart will have the same format
    my $copy = $chart->copy;

You may also make multiple copies . E.g.

    my @copies = $chart->copy(10);  # make 10 copies

=head3 convert

    $chart->convert($imageFmt);

Convert the image format to C<$imageFmt>. See L<Chart Options> for supported
image formats.

=head3 png

    $chart->png;

Change the image format to PNG.

=head3 gif

    $chart->gif;

Change the image format to GIF.

=head3 jpg

    $chart->jpg;

Change the image format to JPEG.

=head3 ps

    $chart->ps;

Change the image format to postscript.

=head3 pdf

    $chart->pdf

Change the image format to PDF.

=head3 command

    $chart->command($gnuplotCommand);

Add a gnuplot command. This method is useful for the Gnuplot features that have
not yet implemented.

=head1 DATASET OBJECT

The dataset object can be initiated by the C<new> method. Properties of the
dataset may be specified optionally when the object is initiated:

    my $dataset = Chart::Gnuplot::DataSet->new(%options);

The data source of the dataset can be specified by either one of the following
ways:

=over

=item 1. Arrays of x values, y values and z values (in 3D plots) of the data
points.

=item 2. Array of data points. Each point is specified as an array of x, y, z
coordinates

=item 3. Data file.

=item 4. Mathematical expression (for a function).

=back

=head2 Dataset Options

=head3 xdata, ydata, zdata

The x, y, z values of the data points. E.g.

    xdata => \@x

If C<xdata> is omitted but C<ydata> is defined, the integer index starting from
0 would be used for C<xdata>.

=head3 points

Data point matrix of the format [[x1,y1], [x2,y2], [x3,y3], ...]

    points => \@points

=head3 datafile

Input data file

    datafile => $file

The data files are assumed to be space-separated, with each row corresponding
to one data point. Lines beginning with "#" are considered as comments and
would be ignored. Other formats are not supported at this moment.

=head3 func

Mathematical function to be plotted. E.g.

    func => "sin(x)*x**3"

Supported functions:

    abs(x)       : absolute value
    acos(x)      : inverse cosine
    acosh(x)     : inverse hyperbolic cosine
    arg(x)       : complex argument
    asin(x)      : inverse sine
    asinh(x)     : inverse hyperbolic sine
    atan(x)      : inverse tangent
    atanh(x)     : inverse hyperbolic tangent
    besj0(x)     : zeroth order Bessel function of the first kind
    besj1(x)     : first order Bessel function of the first kind
    besy0(x)     : zeroth order Bessel function of the second kind
    besy1(x)     : first order Bessel function of the second kind
    ceil(x)      : ceiling function
    cos(x)       : cosine
    cosh(x)      : hyperbolic cosine
    erf(x)       : error function
    erfc(x)      : complementary error function
    exp(x)       : expontial function
    floor(x)     : floor function
    gamma(x)     : gamma function
    ibeta(a,b,x) : incomplete beta function
    inverf(x)    : inverse error function
    igamma(a,x)  : incomplete gamma function
    imag(x)      : imaginary part
    invnorm(x)   : inverse normal distribution function
    int(x)       : integer part
    lambertw(x)  : Lambert W function
    lgamma(x)    : log gamma function
    log(x)       : natural logarithm
    log10(x)     : common logarithm
    norm(x)      : normal distribution function
    rand(x)      : pseudo random number
    real(x)      : real part
    sgn(x)       : sign function
    sin(x)       : sine
    sinh(x)      : hyperbolic sine
    sqrt(x)      : square root
    tan(x)       : tangent
    tanh(x)      : hyperbolic tangent

Please see the Gnuplot manual for updated information.

Supported mathematical constants:

    pi : the circular constant 3.14159...

Supported arithmetic operators:

    addition           : +
    division           : /
    exponentiation     : **
    factorial          : !
    modulo             : %
    multiplication     : *
    subtraction        : -, e.g., 1-2
    unary minus        : -, e.g., -1

Supported logical operations:

    and                      : &&
    complement               : ~
    equality                 : ==
    greater than             : >
    greater than or equal to : >=
    inequality               : !=
    less than                : <
    less than or equal to    : <= 
    negation                 : !
    or                       : ||
    if ... than else ...     : ?:, e.g., a ? b : c

Parametric functions may be represented as hash. E.g.

    func => {x => 'sin(t)', y => 'cos(t)'}

will draw a circle.

=head3 title

Title of the dataset (shown in the legend).

=head3 style

The plotting style for the dataset, including

    lines          : join adjacent points by straight lines
    points         : mark each points by a symbol
    linespoints    : both "lines" and "points"
    dots           : dot each points. Useful for large datasets
    impluses       : draw a vertical line from the x-axis to each point
    steps          : join adjacent points by steps
    boxes          : draw a centered box from the x-axis to each point
    xerrorbars     : "dots" with horizontal error bars
    yerrorbars     : "dots" with vertical error bars
    xyerrorbars    : both "xerrorbars" and "yerrorbars"
    xerrorlines    : "linespoints" with horizontal error bars
    yerrorlines    : "linespoints" with vertical error bars
    xyerrorlines   : both "xerrorlines" and "yerrorlines"
    boxerrorbars   : "boxes" with "yerrorbars"
    boxxyerrorbars : use rectangles to represent the data with errors
    financebars    : finance bars for open, high, low and close price
    candlesticks   : candle sticks for open, high, low and close price
    hbars          : horizontal bars (experimental)
    hlines         : horizontal lines (experimental)

=head3 color

Color of the dataset in the plot. Can be a named color ot RBG (#RRGGBB) value.
The supported color names can be found in the file F<doc/colors.txt> in the
distribution. E.g.

    color => "#99ccff"
    # or
    color => "dark-red"

=head3 width

Line width used in the plot.

=head3 linetype

Line type.

=head3 pointtype

Point type.

=head3 pointsize

Point size of the plot.

=head3 fill

Filling string. Has effect only on plotting styles "boxes", "boxxyerrorbars"
and "financebars".

=head3 axes

Axes used in the plot. Possible values are "x1y1", "x1y2", "x2y1" and "x2y2".

=head3 timefmt

Time format of the input data. The valid format are:

    %d : day of the month, 1-31
    %m : month of the year, 1-12
    %y : year, 2-digit, 0-99
    %Y : year, 4-digit
    %j : day of the year, 1-365
    %H : hour, 0-24
    %M : minute, 0-60
    %s : seconds since the Unix epoch (1970-01-01 00:00 UTC)
    %S : second, 0-60
    %b : name of the month, 3-character abbreviation
    %B : name of the month

=head3 smooth

The smooth method used in plotting data points. Supported methods include cubic
splines (csplines), Bezier curve (bezier) and other. Please see Gnuplot manual
for details.

=head2 Dataset Methods

=head3 new

    my $dataset = Chart::Gnuplot::DataSet->new(%options);

Constructor of the dataset object. If no option is specified, default values
would be used. See L<Dataset Options> for available options.

=head3 copy

Copy the dataset object. This method is especially useful when you want to copy
a dataset with highly customized format. E.g.

    my $dataset = Chart::Gnuplot::DataSet->new(
        ...
    );

    # $copy and $dataset will have the same format and contain the same data
    my $copy = $dataset->copy;

You may also make multiple copies . E.g.

    my @copies = $dataset->copy(10);  # make 10 copies

=head1 EXAMPLES

Some simple examples are shown below. Many more come with the distribution.

=over

=item 1. Plot a mathematical expression

    my $chart = Chart::Gnuplot->new(
        output => "expression.png"
    );

    my $dataSet = Chart::Gnuplot::DataSet->new(
        func => "sin(x)"
    );

    $chart->plot2d($dataSet);

=item 2. Plot from two Perl arrays, one for the x-axis data and the other the
y-axis.

    my $chart = Chart::Gnuplot->new(
        output => "arrays.png"
    );

    my $dataSet = Chart::Gnuplot::DataSet->new(
        xdata => \@x,
        ydata => \@y,
    );

    $chart->plot2d($dataSet);

=item 3. Plot x-y pairs

    # Data
    my @xy = (
        [1.1, -3],
        [1.2, -2],
        [3.5,  0],
        ...
    );

    my $chart = Chart::Gnuplot->new(
        output => "points.png"
    );

    my $dataSet = Chart::Gnuplot::DataSet->new(
        points => \@xy
    );

    $chart->plot2d($dataSet);

=item 4. Plot data from a data file

    my $chart = Chart::Gnuplot->new(
        output => "file.png"
    );

    my $dataSet = Chart::Gnuplot::DataSet->new(
        datafile => "in.dat"
    );

    $chart->plot2d($dataSet);

=item 5. Chart title, axis label and legend

    # Chart object
    my $chart = Chart::Gnuplot->new(
        output => "trigonometric.gif",
        title  => "Three basic trigonometric functions",
        xlabel => "angle in radian",
        ylabel => "function value"
    );

    # Data set objects
    my $sine = Chart::Gnuplot::DataSet->new(
        func  => "sin(x)",
        title => "sine function"
    );
    my $cosine = Chart::Gnuplot::DataSet->new(
        func  => "cos(x)",
        title => "cosine function"
    );
    my $tangent = Chart::Gnuplot::DataSet->new(
        func  => "tan(x)",
        title => "tangent function"
    );

    $chart->plot2d($sine, $cosine, $tangent);

=item 6. Title in non-English characters (Thanks to WOLfgang Schricker)

    use Encode;

    my $title = ...   # Title with German umlauts
    $title = decode("utf8", $title);

    Chart::Gnuplot->new(
        encoding => 'iso-8859-1',
        title    => $title,
    );

=item 7. Plot a financial time series

    my $chart = Chart::Gnuplot->new(
        output   => "dj.ps",
        title    => "Dow-Jones Index time series",
        timeaxis => 'x',
        xtics    => {
            labelfmt => '%b%y',
        },
    );

    my $dow = Chart::Gnuplot::DataSet->new(
        file    => "dj.dat",
        timefmt => '%Y-%m-%d',      # time format of the input data
        style   => "candlesticks",
        grid    => 'on',
    );

    $chart->plot2d($dow);

=item 8. Plot several graphs on the same image

    my $chart = Chart::Gnuplot->new(
        output => "multiplot.gif",
    );

    my $left = Chart::Gnuplot->new();
    my $sine = Chart::Gnuplot::DataSet->new(
        func  => "sin(x)",
    );
    $left->add2d($sine);

    my $center = Chart::Gnuplot->new();
    my $cosine = Chart::Gnuplot::DataSet->new(
        func  => "cos(x)",
    );
    $center->add2d($cosine);

    my $right = Chart::Gnuplot->new();
    my $tangent = Chart::Gnuplot::DataSet->new(
        func  => "tan(x)",
    );
    $right->add2d($tangent);

    # Place the Chart::Gnuplot objects in matrix to indicate their locations
    $chart->multiplot([
        [$left, $center, $right]
    ]);

=back

=head1 FUTURE PLAN

=over

=item 1. Improve the manual.

=item 2. Add more control to the 3D plots.

=item 3. Add curve fitting method.

=item 4. Improve the testsuite.

=item 5. Reduce number of temporary files generated.

=back

=head1 REQUIREMENTS

L<File::Copy>, L<File::Temp>, L<Storable>

Gnuplot L<http://www.gnuplot.info>

ImageMagick L<http://www.imagemagick.org> (for full feature)

=head1 SEE ALSO

Gnuplot official website L<http://www.gnuplot.info>

=head1 AUTHOR

Ka-Wai Mak <kwmak@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008-2010 Ka-Wai Mak. All rights reserved.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
