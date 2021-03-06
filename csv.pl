=head1 NAME

csv.pl

=head1 SYNOPSIS


=head1 DESCRIPTION

Wrap COBOL source files in HTML tags

=head1 AUTHOR

rpillar - <http://www.developontheweb.co.uk/>

=head1 SEE ALSO

=cut

#!/usr/bin/perl;

#use 5.018;

use strict;
use warnings;

use feature 'switch';

use Config::Simple;
use Data::Dumper;
use Getopt::Long;
use List::Compare qw / get_intersection /;

#------------------------------------------------------------------------------
# main 'control' process ..
#------------------------------------------------------------------------------

# the start ...
{

    my $cfg_file;
    GetOptions( "config=s", \$cfg_file );
    unless ( $cfg_file ) {
        usage();
        exit;
    }

    my $cfg = new Config::Simple( $cfg_file );
    my $i_path = $cfg->param('i_path');
    my $o_path = $cfg->param('o_path');
	if ( !$i_path || !$o_path ) {
		print "CSV - please check your config file entries - input / output path entries may be missing\n\n";
		exit;
	}

	print "\nInput Path - $i_path";
	print "\nOutput Path - $o_path\n";
	opendir(BIN, $i_path) or die "Can't open $i_path: $!";

	# process all files in the 'input' folder ...
	while( defined (my $file = readdir BIN) ) {

		# only process files with an extension of 'cbl / CBL'.
		if ( $file =~ /\.cbl$/i ) {
		    print "Processing file : $file\n";
			process ($i_path, $file, $o_path);
		}
		else {
			print "File : $file - ignored\n";
		}
	}
	closedir(BIN);

} # end of main ...

#------------------------------------------------------------------------------
# Process the specified file
#------------------------------------------------------------------------------

sub process {
	my ($i_path, $p_file, $o_path) = @_;

	my $input_name = $p_file;
	$input_name =~ s/i\.txt$|\.cbl$|\.CBL$//;  # remove trailing file extension - 'txt/cbl/CBL'

	my $fullname = $i_path . $p_file;

	if (!open(INFO, "<", $fullname)) {
		die "\nCould not open file : $fullname. Program stopped\n\n";
	}

	# input file
	my @infile = <INFO>;

    # process - initial update of 'program' details, identify 'main' section / copy / paragraph links
	my ( $source1, $sections, $copys ) = add_main_links(\@infile);
	my $source2                        = section_copy_links( $source1, $sections, $copys );
	my $source3                        = process_keywords( $source2 );

	# open output files - initialize as new ...
	my $source_out = $o_path . "/" . $input_name . '.html';

	build_source_list( $source_out, $source3, $sections, $copys, $o_path);

	print "\nProcessed file : $p_file\n";


	# close files
	close(INFO);
}

#------------------------------------------------------------------------------
# add the 'main' links - DIVISION / SECTION etc.
#------------------------------------------------------------------------------

sub add_main_links {
    my $file = shift;

    # variables ...
	my @words;
	my @source;
	my $line_no     = 0;
	my $procedure   = 0;
	my $copy_tag    = 0;
	my $section_tag = 0;
	my %sections;
	my %copys;

	foreach my $line ( @{$file} ) {
		$line =~ s/\r|\n//g;    # remove carriage returns / line feeds
		chomp $line;            # just in case !!!
		my $length_all = length($line);

		# blank line - just set to 'area A' - spaces
		if ( $length_all == 0 ) {
			$source[$line_no] = "        ";
			$line_no++;
			next;
		}

		# split 'line' - area 'A' / 'B' (assumes margings at 8 and 72) - not strictly true from a COBOL perspective but ...
		my ( $area_A, $area_B ) =  unpack("(A7A65)",$line);

		# process 'comment' / 'break' lines first ...
		if (substr($area_A, 6, 1) eq '*') {
			$source[$line_no] = "<span class=\"comment\">".$line."</span>";
		}
		elsif (substr($area_A, 6, 1) eq '/') {
			$source[$line_no] = "<span class=\"break\">".$line."</span>";
		}

        ### process 'DIVISION' statements ###
		elsif ( $line =~ /DIVISION/i) {
			@words = split(/ /, $area_B);

			given ( $words[0] ) {
                when (/IDENTIFICATION/i ) {
			        $source[$line_no] = "<span class=\"div_name\"><a name=\"Id_Div\">".$line."</a></span>";
		        }
			    when ( /ENVIRONMENT/i) {
				    $source[$line_no] = "<span class=\"div_name\"><a name=\"Env_Div\">".$line."</a></span>";
			    }
			    when ( /DATA/i) {
				    $source[$line_no] = "<span class=\"div_name\"><a name=\"Data_Div\">".$line."</a></span>";
			    }
			    when ( /PROCEDURE/i) {
				    $source[$line_no] = "<span class=\"div_name\"><a name=\"Proc_Div\">".$line."</a></span>";
				    # if I have reached the 'procedure' division then set this flag - used later ...
			 	    $procedure = 1;
			    }
		    }
			@words=(); # reset ...
		}

        ### process 'SECTION' names ###
		elsif( $line =~ /\sSECTION[.]/i) {
			$section_tag++;
			@words = split(/\s/, $area_B);

			# these SECTIONs should always appear 'above' the PROCEDURE division ...
			unless ($procedure) {
				given ( $words[0] ) {
				    when ( /INPUT-OUTPUT/i ) {
					    $source[$line_no] = "<span class=\"section_name\"><a name=\"InOut_Sec\">".$line."</a></span>";
				    }
				    when ( /FILE/i ) {
					    $source[$line_no] = "<span class=\"section_name\"><a name=\"File_Sec\">".$line."</a></span>";
				    }
				    when ( /WORKING-STORAGE/i ) {
					    $source[$line_no] = "<span class=\"section_name\"><a name=\"WS_Sec\">".$line."</a></span>";
				    }
				    when ( /LINKAGE/i ) {
					    $source[$line_no] = "<span class=\"section_name\"><a name=\"Link_Sec\">".$line."</a></span>";
				    }
				    when ( /CONFIGURATION/i ) {
					    $source[$line_no] = "<span class=\"section_name\"><a name=\"Conf_Sec\">".$line."</a></span>";
				    }
			    }
			}

			# store 'sections' and add a named 'link' ...
			else {
				$sections{$words[0]}      = "#SEC$section_tag";
				$source[$line_no]         = "<a name=\"SEC$section_tag\">".$line."</a>";
			}
			@words=(); # reset ...
		}

	    ### process 'COPY' names ###
		elsif( $line =~ / COPY /i) {
			$copy_tag++;
			@words = split(/ +/, $area_B);

			$words[2] =~ s/\.$//;
			$copys{$words[2]}="#COPY$copy_tag";
			$source[$line_no] = $line;
		}

        ### process other 'names' that start in position 8 - 'PARAGRAPH' names ###

		else {
			@words = split(/ /, $area_B);
			if ( @words ) {
			    if ( (substr($area_B, 0, 1) ne " ") && $procedure) {
				    $section_tag++;
				    $words[0]                 =~ s/\.$//;

				    $sections{$words[0]}      = "#SEC$section_tag";
				    $source[$line_no]         = "<a name=\"SEC$section_tag\">".$line."</a>";
			    }
			    else {
				    $source[$line_no] = $line;
			    }
			}
			else {
				$source[$line_no] = $line;
			}
			@words=();
		}

	    $line_no++;
	}

    # return initial 'program' listing, section names, copy names
    return ( \@source, \%sections, \%copys );
}

#------------------------------------------------------------------------------
# process the links for Section / Copy names / Go Tos etc ###
#------------------------------------------------------------------------------

sub section_copy_links {
    my ( $source, $sections, $copys ) = @_;

	my $line_no = 0;
	foreach my $line ( @{$source} ) {

		### ignore 'comment' / 'break' lines
		if ( $line =~ /comment/i || $line =~ /break/i ) {
			$line_no++;
			next;
		}

		my ( $area_A, $area_B ) =  unpack("(A7A65)",$line);

        ### process 'PERFORM' statements - add links to enable navigation to the appropriate 'section' ###
		if ( $line =~ /\sPERFORM/i) {
			my @words = split(/ +/, $area_B);

			# remove 'period' at end of name (if it exists)
			if ($words[2] =~ /\.$/) {
				chop($words[2]);
			}

            ### check if this 'word' is in SECTION hash ###
			if (exists ( $sections->{$words[2]} ) ) {
				my $section_name = $words[2];
				my $p_tag = $sections->{$section_name};

				### get position of PERFORM ###
				my $start = index( uc($area_B), 'PERFORM' );
				my $href = "<a class=\"smoothScroll\" href=\"$p_tag\">";

				### indent the PERFORM / 'link' by the correct amount ###
				my $new_line = $area_A;
				my $indent = $start + 1;
				$new_line = $new_line.( ' ' x $indent);
				$new_line = $new_line . $href;

				my $perform_name_len  = length($area_B) - $start;
				my $perform_name      = substr($area_B, $start, $perform_name_len);
				$new_line             = $new_line . $perform_name . "</a>";

				### updated 'line'
				@{$source}[$line_no] = $new_line;
			}

			$line_no++;
			next;
		}

        ### process 'COPY' statements ###

		if ( $area_B =~ /COPY /i) {
			my @words = split(/ +/, $area_B);

			# remove 'period' at end of COPY name (if it exists)
			if ($words[2] =~ /\.$/) {
				chop($words[2]);
			}

			### check if in COPY hash ###
			if (exists ( $copys->{$words[2]} ) ) {
				my $copy_member_name = $words[2];
				my $c_tag            = $copys->{$copy_member_name};

				### get position of COPY ###
				my $start = index( uc($area_B), 'COPY' );
				my $href  = "<a href=\"$c_tag\">";

				### indent the COPY / 'link' by the correct amount ###
				my $new_line = $area_A;
				$new_line = $new_line.( ' ' x $start );
				$new_line = $new_line . $href;

				my $copy_name_len = length($area_B) - $start;
				my $copy_name     = substr($area_B, $start, $copy_name_len);
				$new_line         = $new_line . $copy_name . "</a>";

				### updated 'line'
				@{$source}[$line_no] = $new_line;
			}

			$line_no++;
			next;
		}

        ### process 'GO TO' statements ###

		if ( $area_B =~ /GO TO/i) {
			my @words = split(/ +/, $area_B);

			# remove 'period' at end of GO TO name (if it exists)
			if ($words[3] =~ /\.$/) {
				chop($words[3]);
			}

			### check if in SECTIONS hash ###
			if (exists ( $sections->{$words[3]} ) ) {
				my $goto_label_name = $words[3];
				my $g_tag           = $sections->{$goto_label_name};

				### get position of the GO TO ###
				my $start = index( uc($area_B), 'GO TO' );
				my $href = "<a class=\"smoothScroll\" href=\"$g_tag\">";

				### indent the GO TO / 'link' by the correct amount ###
				my $new_line = $area_A;
				$new_line = $new_line.( ' ' x $start );
				$new_line = $new_line . $href;

				my $goto_name_len = length($area_B) - $start;
				my $goto_name     = substr($area_B, $start, $goto_name_len);
				$new_line         = $new_line . $goto_name . "</a>";

				### updated 'line'
				@{$source}[$line_no] = $new_line;
			}

			$line_no++;
			next;
		}

		$line_no++;
	}

	return $source;
}

#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------
sub process_keywords {
	my $source = shift;

	my @words;
	my @WORDS;

	my @program;

	# COBOL keywords - probably not the 'definitive' list ...
	my @keywords = ('SECTION', 'PERFORM', 'END-PERFORM', 'MOVE', 'TO', 'IF', 'END-IF', 'EVALUATE', 'END-EVALUATE',
			'INSPECT', 'TALLYING', 'FROM', 'UNTIL', 'COMPUTE', 'FOR', 'OF', 'BY', 'INTO', 'SET', 'DISPLAY', 'CLOSE');

	my $line_no = 0;
	my $in_procedure_div = 0;

	foreach ( @{$source} ) {

		# check for 'keywords' in the PROCEDURE division
		if ( /PROCEDURE/i ) {
			$in_procedure_div = 1;
		    $program[$line_no] = $_;
			$line_no++;
			next;
		}

		if ( !$in_procedure_div ) {
		    $program[$line_no] = $_;
			$line_no++;
			next;
		}

		if ( $in_procedure_div ) {
			# ignore 'comment' lines
			if ( /comment/i )
			{
				$program[$line_no] = $_;
				$line_no++;
				next;
			}
			else
			{
				# ignore 'GO TO' lines
				if ( /GO TO/i )
				{
					$program[$line_no] = $_;
					$line_no++;
					next;
				}
				else
				{
					my ( $area_A ) =  unpack( "(A7)", $_ );
					@words = split(/ +|\./, $_);
					@WORDS = map { uc } @words;
					my $lc = List::Compare->new('--unsorted', \@keywords, \@WORDS);
					my @intersection = $lc->get_intersection;

			 		# process 'keywords'
			 		my $keyword_span       = "<span class=\"keyword\">";
			 		my $keyword_span_close = "</span>";
			 		my $line = $_;

					#foreach my $match (@intersection) { # comment out for now !!
					#		my $start = index( uc($line), $match );
					#	my $prefix = substr($line, 0, $start);
					#
					#	my $keyword_length = length($match);
					#	my $keyword        = substr($line, $start, $keyword_length);
					#
					#	my $suffix_length = length($line) - ($start + $keyword_length);
					#	my $suffix = substr( substr($line,7), $start + $keyword_length, $suffix_length);
					#	$line   = $area_A . $prefix . $keyword_span . $keyword . $keyword_span_close . $suffix;
					#}
					$program[$line_no] = $line;
					$line_no++;
				}
				#$program[$line_no] = $_;
				#$line_no++;
			}
		}
		#$program[$line_no] = $_;
		#$line_no++;
	}

	return \@program;
}

#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------
sub build_source_list {
	my ( $file_out, $program, $sections_list, $copys, $o_path ) = @_;

	if ( !open(OUT, ">", $file_out) ) {
		print "Unable to open output file : $file_out -  exit !!!\n";
		exit;
	}

	print OUT "<!DOCTYPE html>";
	print OUT "<html>";
	print OUT "<head>";
	print OUT "<meta charset=\"utf-8\">";
	print OUT "<title>COBOL Source Viewer</title>";
	print OUT "<link rel=\"stylesheet\" type=\"text/css\" href=\"css/bootstrap.min.css\">";
	print OUT "<link rel=\"stylesheet\" type=\"text/css\" href=\"css/styles.css\">";
	print OUT "<link href='http://fonts.googleapis.com/css?family=Lobster' rel='stylesheet' type='text/css'>";
	print OUT "<script src=\"http://ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js\"></script>";
	print OUT "<script src=\"js/smoothscroll.js\"></script>";
	print OUT "</head>";
	print OUT "<body>";

	### sort out divisions / sections / procedure links
	print OUT "<aside id=\"left_links\">";

	    ### display icon
	    print OUT "<div id=\"icon\">";
		    print OUT "<h1 style=\"text-align:center;\"><span style=\"border-bottom:1px solid #000;font-family:Lobster;\" >CSV</span></h1>" . "<br>";
		print OUT "</div>";

	    ### display 'divisions list and links
	    print OUT "<div id=\"divisions\">";
		    print OUT "<a href=\"#top\" class=\"div_link smoothScroll\">Identification Division</a>";
		    print OUT "<br>" . "<a href=\"#Env_Div\" class=\"div_link smoothScroll\">Environment Division</a>";
		    print OUT "<br>" . "<a href=\"#Data_Div\" class=\"div_link smoothScroll\">Data Division</a>";
		    print OUT "<br>" . "<a href=\"#WS_Sec\" class=\"div_link smoothScroll\">Working Storage</a>";
		    print OUT "<br>" . "<a href=\"#Link_Sec\" class=\"div_link smoothScroll\">Linkage Section</a>";
		    print OUT "<br>" . "<a href=\"#Proc_Div\" class=\"div_link smoothScroll\">Procedure Division</a>";
		    print OUT "<br>" . "<br>";
	    print OUT "</div>";

        ### sort the sections list and place on page
	    print OUT "<div id=\"sections_list\">";
	        my $href1 = "<a class=\"smoothScroll\" href=\"";
	        my $href2 = "\">";
	        my @sections_keys = keys %{$sections_list};
	        @sections_keys    = sort(@sections_keys);

	        foreach my $section ( @sections_keys ) {
	            if ( $section eq 'x' ) {
	                next;
	            }
		        print OUT $href1 . $sections_list->{$section} . $href2 . $section . " <a/>" . "<br>";
	        }
	    print OUT "</div>";

	print OUT "</aside>";

	print OUT "<section style=\"border: 0 solid lightblue;display:block;float:left;width:65%;position:relative;\">";

		# code ...
		print OUT "<div style=\"margin:20px;padding-left:250px;border-right:1px solid lightblue;width:100%;min-width:850px;\">";

			print OUT "<div id=\"code\">";

				print OUT "<pre>";
			    print OUT "<div><span id=\"top\"></span></div>";
				foreach my $line ( @{$program} ) {
					if ( $line ) {
					    print OUT $line . "<br>";
				    }
				}
	    		print OUT "</pre>";
			print OUT "</div>";
		print OUT "</div>";

	print OUT "</section>";

	### copybook links
    print OUT "<section style=\"display:block;float:left;width:30%;position:relative;\">";

        print OUT "<div style=\"margin-top:50px;margin-left:50px;\">";

	        print OUT "<div><h3><span style=\"border-bottom: 1px solid #000;\">CopyBooks</span></h3>" . "<br>" . "</div>";

            ### sort the copybook list and place in html page ###
	        print OUT "<div id=\"copybooks\">";
	            $href1 = "<a href=\"" . $o_path . "copy/";
	            $href2 = " .html\"target=\"_blank\">";

	            my @sorted_copy = keys %{$copys};
	            @sorted_copy    = sort(@sorted_copy);

	            my $size = @sorted_copy;
                if ( $size ) {
	                foreach my $copy ( @sorted_copy ) {
	         	        if ( $copy eq 'x') {
	           	       	    next;
	           	        }
		                print OUT $href1 . $copys->{$copy} . $href2 . $copy . " <a/>" . "<br>";
	                }
		        }
			    else {
			        print OUT "<p style=\"text-align:left;\">( None )</p>";
			    }
	        print OUT "</div>";

	    print OUT "</div>";

	print OUT "</section>";

	print OUT "</body>";
	print OUT "</html>";
}

#------------------------------------------------------------------------------
# usage.
#------------------------------------------------------------------------------
sub usage {
    print "\nPerl script - csv.pl\n";
	print "\nError - a config file path needs to be specified\n";
	print "Usage :- perl CSV.pl --config='xyz.cfg' \n\n";
}
