package Object::Attributed;
use strict;
use warnings;
use v5.14;
use Carp 'croak';
#use Safe ();
use Clone 'clone';
use Data::Dumper 'Dumper';
use Attribute::Handlers;
use Class::ISA ();
use Package::Stash ();
use B ();

our $VERSION=1.01;

BEGIN
{
	push @Carp::CARP_NOT,'Attribute::Handlers';
}

use constant specifiers=>qw/read write name getter setter handler/;
{
	no strict 'refs';
	for my $spc (specifiers)
	{
		*$spc=sub{$spc};
	}
}

INIT
{
	no strict 'refs';
	for my $spc (specifiers)
	{
		undef *$spc;
	}
}

my $defaults;
#my $safe=Safe->new;

my $find_method_tentative=sub
{
	my ($class,$method)=@_;
	my @parents=Class::ISA::super_path($class);
	foreach ($class,@parents)
	{
		my $stash=Package::Stash->new($_);
		if(my $ref=$stash->get_symbol("&$method"))
		{
			return($_,$ref);
		}
	}
	undef;
};

our %init_lists=('Object::Attributed'=>{create=>{list=>[]}});

sub Init: ATTR(CODE,RAWDATA)
{
	my ($package,$symbol,$code,$attr,$data)=@_;
	my $ctor=*$symbol{NAME};
	#print "INIT $package->$ctor, DATA: [$data].\n";
	my ($prop,$value,$direct,$first_time);
	if(!(($prop,$value)=$data=~/^(.+?)\((.+)\)$/))
	{
		if(!(($prop,$value)=$data=~/^(.+?)=(.+)$/))
		{
			die "Unable to parse initializer expression for constructor \"$package\::$ctor\".";
		}
		else
		{
			$direct=1;
		}
	}
	my @parents=Class::ISA::super_path($package);
	if(!exists $init_lists{$package}{$ctor})
	{
		$first_time=1;
		$init_lists{$package}{$ctor}{$package}{list}=[];
		foreach my $cls (@parents)
		{
			$init_lists{$package}{$ctor}{$cls}{list}=clone($init_lists{$cls}{$ctor}{list}) // [];
		}
	}
	push @{$init_lists{$package}{$ctor}{$package}{list}},
	{
		direct=>$direct,
		name=>$prop,
		value=>$value,
	};
	foreach my $cls (@parents)
	{
		my $a=$init_lists{$package}{$ctor}{$cls}{list};
		foreach my $i (0..scalar @$a-1)
		{
			if($a->[$i]->{name} eq $prop)
			{
				splice(@$a,$i,1);
			}
		}
	}
	#my $cv=B::svref_2object(\&$symbol);
	no warnings 'redefine';
	*$symbol=sub
	{
		my @copy=@_;
		my $self=$_[0];
		goto &$code if $self->{__created};
		my %ARGS=@_[1..$#_];
		foreach my $def (@{$init_lists{ref $self}{$ctor}{$package}{list}})
		{
			my @values=eval "my \@copy;package $package;$def->{value}";
			$@ and die $@;
			my $prop=$def->{name};
			if($def->{direct})
			{
				$self->{$prop}=@values;
			}
			else
			{
				$self->$prop(@values);
			}
		}
		@_=@copy;
		goto &$code;
	} if $first_time;
}

package Object::Attributed::implicit_handlers;
# hide this from being inherited by subclasses and also allows to check the package later
# to supply these two access handlers with the property name they are dealing with.
sub getter
{
	return $_[0]->{$_[1]};
};
sub setter
{
	$_[0]->{$_[1]}=$_[2];
	return $_[0];
};

package Object::Attributed;

sub Prop: ATTR(CODE,RAWDATA)
{
	use subs specifiers;
	my ($package,$symbol,$code,$attr,$data,$phase,$filename,$linenum)=@_;
	my ($access,$mod,$prop,$methods);
	$prop=*$symbol{NAME};
	my ($flags,%buf)=eval "return ($data)";
	$@ and die $@;
	my $cv=B::svref_2object($code);
	undef $code if ref $cv->START eq 'B::NULL';
	if(ref $flags ne 'ARRAY')
	{
		$flags=[$flags];
	}
	foreach (@$flags)
	{
		$access->{$_}=1 when $_~~['read','write'];
		$mod->{$_}=1 when $_~~['getter','setter'];
		$mod->{name}{setter}=$mod->{name}{getter}=1 when 'name';
		default
		{
			die "Unvalid specifier or modificator \"$_\"!";
		}
	}
	my $cntr=0;
	if($buf{handler})
	{
		$mod->{handler}=$methods->{getter}=$methods->{setter}=$buf{handler};
	}
	else
	{
		foreach ('g','s')
		{
			my $m=$buf{"${_}etter"};
			if($m)
			{
				$methods->{"${_}etter"}=$m;
				++$cntr;
			}
		}
		if(!$cntr)
		{
			if($mod->{setter})
			{
				$methods->{setter}=$code;
			}
			elsif($mod->{getter})
			{
				$methods->{getter}=$code;
			}
		}
		elsif($cntr==1)
		{
			if($methods->{setter})
			{
				$methods->{getter}=$code;
			}
			else
			{
				$methods->{setter}=$code;
			}
		}
	}
	foreach ('g','s')
	{
		if(!$methods->{"${_}etter"})
		{
			if(my $m=$package->can("${_}et_$prop"))
			{
				$methods->{"${_}etter"}=$m;
			}
			else
			{
				$methods->{"${_}etter"}=$_ eq 'g' ? \&Object::Attributed::implicit_handlers::getter :
					\&Object::Attributed::implicit_handlers::setter;
				#print "$prop ($package) gets implicit ${_}et handler.\n";
			}
		}
	}
	foreach ('g','s')
	{
		my $m=$methods->{"${_}etter"};
		if(ref $m ne 'CODE')
		{
			my ($p,$mm) = $m=~/^(?:(.*)::)?(\w+)$/;
			my ($source,$recipient)=(Package::Stash->new($p || $package),Package::Stash->new($package));
			$recipient->add_symbol("&${_}et_$prop",($source->get_symbol("&$mm") or
				die "Undefined ${_}etter \"$m\" for property $prop in $package!"),filename=>$filename,first_line_num=>$linenum);
			$m=$recipient->get_symbol("&${_}et_$prop");
		}
		else
		{
			my $stash=Package::Stash->new($package);
			$stash->add_symbol("&${_}et_$prop",$m,filename=>$filename,first_line_num=>$linenum);
		}
		my $cv=B::svref_2object($m);
		$mod->{name}{"${_}etter"}=1 if $cv->GV->STASH->NAME eq 'Object::Attributed::implicit_handlers';
	}
	exists $buf{value} and $defaults->{$package}{$prop}=$buf{value};
	no warnings 'redefine';
	*$symbol=sub
	{
		my $skip_name=!defined $_[0];
		my $self=$skip_name ? shift : $_[0];
		my @modes=(
		{
			name=>'read',
			prefix=>'g'
		},
		{
			name=>'write',
			prefix=>'s'
		});
		my $mode=@_>1;
#		print uc($modes[$mode]->{name})." ACCESS $prop in ".ref($self)." (static type $package) ".Dumper(\@_);
		croak "$prop is $modes[1-$mode]->{name}-only." unless $access->{$modes[$mode]->{name}};
		my $m="$modes[$mode]->{prefix}et_$prop";
		my (undef,$handler)=$find_method_tentative->($package,$m);
		croak "Undefined $modes[$mode]->{name} property handler for $prop!" unless defined $handler;
		splice(@_,1,0,$prop) if $mod->{name}{"$modes[$mode]->{prefix}etter"} && !$skip_name;
		unshift @_,undef if $mod->{handler};
#		print "END $prop ".Dumper(\@_,$mod,$access,$methods);
		goto &$handler;
	};
	return;
}

sub __created : Prop(read,value=>0);

sub new
{
	my $class=shift;
	my $x=clone($defaults->{$class}) // {};
	my $obj=bless $x,$class;
	$obj->create(@_);
	$obj->{__created}=1;
	return $obj;
}

sub create {}

1;
