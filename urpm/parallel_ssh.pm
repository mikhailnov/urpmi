package urpm::parallel_ssh;

#- parallel resolve_dependencies
sub parallel_resolve_dependencies {
    my ($parallel, $synthesis, $urpm, $state, $requested, %options) = @_;

    #- first propagate the synthesis file to all machine.
    foreach (keys %{$parallel->{nodes}}) {
	$urpm->{log}("parallel_ssh: scp -q '$synthesis' '$_:$synthesis'");
	system "scp -q '$synthesis' '$_:$synthesis'";
    }
    $parallel->{synthesis} = $synthesis;

    #- compute command line of urpm? tools.
    my $line = $options{auto_select} ? ' --auto-select' : '';
    foreach (keys %$requested) {
	if (/\|/) {
	    #- taken from URPM::Resolve to filter out choices, not complete though.
	    my $packages = $urpm->find_candidate_packages($_);
	    foreach (values %$packages) {
		my ($best_requested, $best);
		foreach (@$_) {
		    exists $state->{selected}{$_->id} and $best_requested = $_, last;
		    exists $avoided{$_->name} and next;
		    if ($best_requested || exists $requested{$_->id}) {
			if ($best_requested && $best_requested != $_) {
			    $_->compare_pkg($best_requested) > 0 and $best_requested = $_;
			} else {
			    $best_requested = $_;
			}
		    } elsif ($best && $best != $_) {
			$_->compare_pkg($best) > 0 and $best = $_;
		    } else {
			$best = $_;
		    }
		}
		$_ = $best_requested || $best;
	    }
	    #- simplified choices resolution.
	    my $choice = $options{callback_choices}->($urpm, undef, $state, [ values %$packages ]);
	    $choice and $line .= ' '.$choice->fullname;
	} else {
	    my $pkg = $urpm->{depslist}[$_] or next;
	    $line .= ' '.$pkg->fullname;
	}
    }

    #- execute urpmq to determine packages to install.
    my ($node, $cont, %chosen);
    local (*F, $_);
    do {
	$cont = 0; #- prepare to stop iteration.
	#- the following state should be cleaned for each iteration.
	delete $state->{selected};
	#- now try an iteration of urpmq.
	foreach my $node (keys %{$parallel->{nodes}}) {
	    $urpm->{log}("parallel_ssh: ssh $node urpmq --synthesis $synthesis -f $line ".join(' ', keys %chosen));
	    open F, "ssh $node urpmq --synthesis $synthesis -fdu $line ".join(' ', keys %chosen)." |";
	    while ($_ = <F>) {
		chomp;
		if (/\|/) {
		    #- distant urpmq returned a choices, check if it has already been chosen
		    #- or continue iteration to make sure no more choices are left.
		    $cont ||= 1; #- invalid transitory state (still choices is strange here if next sentence is not executed).
		    unless (grep { exists $chosen{$_} } split '\|', $_) {
			my $choice = $options{callback_choices}->($urpm, undef, $state, [ map { $urpm->search($_) } split '\|', $_ ]);
			if ($choice) {
			    $chosen{scalar $choice->fullname} = $choice;
			    #- it has not yet been chosen so need to ask user.
			    $cont = 2;
			} else {
			    #- no choices resolved, so forget it (no choices means no choices at all).
			    $cont = 0;
			}
		    }
		} else {
		    my $pkg = $urpm->search($_) or next; #TODO
		    $state->{selected}{$pkg->id}{$node} = $_;
		}
	    }
	    close F or $urpm->{fatal}(1, _("host %s does not have a good version of urpmi", $node));
	}
	#- check for internal error of resolution.
	$cont == 1 and die "internal distant urpmq error on choice not taken";
    } while ($cont);

    #- keep trace of what has been chosen finally (if any).
    $parallel->{line} = "$line ".join(' ', keys %chosen);

    #- update ask_remove, ask_unselect too along with provided value.
    #TODO
}

#- parallel install.
sub parallel_install {
    my ($parallel, $urpm, $remove, $install, $upgrade) = @_;

    foreach (keys %{$parallel->{nodes}}) {
	my $sources = join ' ', map { "'$_'" } values %$install, values %$upgrade;
	$urpm->{log}("parallel_ssh: scp $sources $_:$urpm->{cachedir}/rpms");
	system "scp $sources $_:$urpm->{cachedir}/rpms";
    }

    my %bad_nodes;
    foreach my $node (keys %{$parallel->{nodes}}) {
	local (*F, $_);
	$urpm->{log}("parallel_ssh: ssh $node urpmi --no-locales --test --no-verify-rpm --auto --synthesis $parallel->{synthesis} $parallel->{line}");
	open F, "ssh $node urpmi --no-locales --test --no-verify-rpm --auto --synthesis $parallel->{synthesis} $parallel->{line} |";
	while ($_ = <F>) {
	    $bad_nodes{$node} .= $_;
	    /Installation failed/ and $bad_nodes{$node} = '';
	    /Installation is possible/ and delete $bad_nodes{$node}, last;
	}
	close F;
    }
    foreach (keys %{$parallel->{nodes}}) {
	exists $bad_nodes{$_} or next;
	$urpm->{error}(_("Installation failed on node %s", $_) . ":\n" . $bad_nodes{$_});
    }
    %bad_nodes and return;

    #- continue installation on each nodes.
    foreach my $node (keys %{$parallel->{nodes}}) {
	$urpm->{log}("parallel_ssh: ssh $node urpmi --no-locales --no-verify-rpm --auto --synthesis $parallel->{synthesis} $parallel->{line}");
	system "ssh $node urpmi --no-locales --no-verify-rpm --auto --synthesis $parallel->{synthesis} $parallel->{line}";
    }
    1;
}


#- allow bootstrap from urpmi code directly (namespace is urpm).
package urpm;
sub handle_parallel_options {
    my ($urpm, $options) = @_;
    my ($id, @nodes) = split ':', $options;

    if ($id =~ /^ssh(?:\(([^\)]*)\))?$/) {
	my %nodes; @nodes{@nodes} = undef;

	return bless {
		      media   => $1,
		      nodes   => \%nodes,
		     }, "urpm::parallel_ssh";
    }

    return undef;
}

1;
