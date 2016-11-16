# COPYRIGHT
# Copyright (c) 2016 Alexandrov Denis. All rights reserved. This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
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

our $VERSION=1.02;

=head1 DESCRIPTION

This library automatically creates property getters and setters via the help of the special Prop attribute.
All properties can be specified as read and/or write, meaning they can be retrivied and/or set, respectively.
You can also supply a default value, otherwise it will be undefined.
The library also supports member initialization similar to C++ member initialization.
The whole design was inspired by Delphi's OOP system, but in line with Perl's more open general nature.
The initialization feature is inspred by C++ member initialization, with adaptations to Perl.

The module aims to stay with the spirit of the simplistic Perl's built-in class system, only enhancing it.
No fancy features like roles are planned. It also doesn't introduce new keywords like 'has' either, something
I personally never liked. You don't have to change much about your classes if you want to switch to use the features of
this library. All general remarks about Perl's OOP model apply to classes produced with help of Object::Attributed.
Many probably will pass by after reading this, but personally I'm really fond of that.

=head1 SYNOPSIS

	package Human;
	# use clause here.
	use parent 'Object::Attributed'; #no imports available.

	sub name : Prop([read,write,setter],value=>'Joe') # 'sub' is important, see below;
	# this declares a read-write property named 'name'.
	# 'setter' means the code of the sub that follows as in a regular subroutine after
	# is taken as the setter. No getter is specified, so implicit one is used.
	# 'Joe' is the default value for the property.
	{
		# the setter body here.
		my $self=shift;
		my ($value)=@_;
		croak 'Invalid name.' unless $value && $value=~/[\w\s]+/;
		return $self; #if you want to support method chaining. Implicit setters do.
	}

	sub create : Init(name($_[1] || 'Joe')) # the constructor. The 'Init' attribute is discussed later.
	{
		my $self=shift;
		print "Hello, World! I'm $self->{name}!"; # 'name' is already initialized by either an argument to 'create'
		# or the aternative 'Joe'.
	}

	<somewhere in the main program>
	use Human;

	...

	my $person=Human->new('Lisa');
	print $person->name('Elisabeth')->name; # grown up!

=head1 DECLARING AND USING PROPERTIES

The syntax is:

	sub PROPERTY_NAME : Prop([ACCESSORS,MODIFIERS],\%{PARAMETERS})
	{
		#optional body.
	}

PROPERTY_NAME is the name of the property you want to declare. Must be a valid Perl identifier.
ACCESSORS can is an array ref consisting of the following values:

	read write

At least one of them is mandatory.

MODIFIERS follow the same format, the allowed values are:

	setter getter name

Together modifiers and accessors are called specifiers within this document. They can also be optionally
enclosed in quotes as regular Perl strings. If only one specifier is present, it can be given as a literal
string with its name instead of inside reference to an anonymous array: C<[read]>.

'setter' and 'getter' are mutually exclusive but either one is required if no handlers are specified at all in PARAMETERS.
'name' is optional.

=over

=item *

'read' states the property can be read from, 'write' - written/assigned to.

=item *

'setter'/'getter' are used when there are no explicit accessors provided in PARAMETERS. They mean the body
of the subroutine the Prop attribute is applied to is the getter/setter of the property. This means they are mutually
exclusive and shouldn't be used together.

=item *

'name' states the handlers will be provided the name of the property
as the second parameter, after C<$self> AKA C<$_[0]>. This allows to reuse handlers of one property
for others, should they only differ in names. Also may be of interest for informational purposes. See
PARAMETERS below.

=back

PARAMETERS are given inline as key-value pairs (C<< key=>value,... >>). Internally they will be slurped into
one hash. Supported parameters are

=over

=item *

	getter=>'string' || sub {...} || $code_ref
	setter=>'string' || sub {...} || $code_ref

Specifies the getter and the setter for the property. Only one is mandatory, and only if no 'getter'/'setter'
modifier is supplied. Normally you want to use the sub's body for either one, and
specify the other here, this is done automatically by the module, so no need to pass the two parameter at the same time usually.
The logic is to look if I<either> getter or a setter is supplied, in this case the unspecified one takes the sub's body for itself.
Otherwise read/write handler takes the body for itself according to the 'getter'/'setter' modifier, that clarify
what handler gets the body, and the other handler will be assigned an implicit accessor. And if both were supplied at the same
time, when just take that as is. Everyone should be happy.
Each of the parameters take the same input. The first form specifies, possibly fully qualified,
a given method to use as the handler, unqualified names assume the package of the property. The second
specifies the handler's code inline inside the brackets; you have full freedom here to write any Perl code
as in a normal subroutine. And the last just takes whatever the reference points to as the
handler. You can, in theory, specify both, completely omitting the subroutine's own body from being used at all.

=item *

	handler=>'string' || sub {...} || $code_ref

Specifies the handlers for BOTH read and write accessors, so is just a shortcut
for setting both the last parameters at the same value. Optional. It means the same code is responsible to handle B<both>
reading and writing to the property! Takes the same format of input as the previous two parameters.

=item *

	value=>EXPRESSION

Specifies the default value for the property as a valid Perl expression. Optional. If set and is
not undef, all newly created objects will get a I<copy> of the value via Clone::clone. As such, it means complex
data like objects might not be copied properly; using it might also mean double initialization if later your constructor
decides to assign it a new value. See "USING MEMBER INITIALIZATION" below for a better way to initialize members of your classes.

The expression is evaluated only once, at processing of the property declaration. The returned value is copied later.

=back

=head1 USING MEMBER INITIALIZATION

The default values for properties are good only if your objects are simple in structure and you don't need to change
the them dynamically in the constructor nor to trigger write accessors. For other cases there is member initialization.

	sub create : Init(name($_[1] || 'Joe'))
	sub create : Init(name=$_[1] || 'Joe')

First form will invoke C<< $obj->name($_[1] || 'Joe') >>. The second C<< $obj->{name}=$_[1] || 'Joe' >>. So the
first form is suitable if you need to run the corresponding write accessor, while the second will directly update
the key in the object's hash with provided value. Here 'name' is taken from the previous example. It can be any
method name of the object that handles the initialization, in the first form that is. It just happens that
property write accessors do that intrinsically, but you are not required to use them. The feature is smart enough to avoid
re-initialization of the same member more than once. If a parent of a class anywhere in the hierarchy specifies an
initializator for the same member, the child's declaration wins, and the parent's will never be considered afterwards.
The expression in the parentheses or after the equal sign is any valid Perl expression. It will be evaluated once per initializator
per construction of an object. It is run in context of the constructor, so any arguments provided here are available to the expression.
That's how you can use user supplied arguments here w/ just an '||' or '//' operator. You can modify the contents of the C<@_>
array, but it will be restored to its initial value before the actual constructor code runs, as a precaution measure.
Remember the first element in the array is the C<$self> parameter. For convenience, a special variable named C<%ARGS>
is provided, a hash with the contents of C<@_> w/o C<$self>, to work with named arguments. The implementation of this is naive,
so mixed arguments may emit odd-sized hash warnings. The initializations all happen once the constructor is invoked, but before
its code has any chance to do anything. It means that it will see already updated values, if any.

Multiple initializers on the same member in the same class are valid. The order of initialization matches the order of declaration.

To run a parent's iniialization list, you must call its inherited constructor at some point before returning from yours. Once you
do return, any calls to any of constructors won't have any initialization effect.

=head1 IMPLICIT ACCESSORS

If the setter or the getter of a code didn't get any explicit handler assigned or deduced from input arguments, it will
get an implicit one. An implicit getter simply returns C<<$obj->{PROP}>>, while implicit setter does

	$_[0]->{PROP}=VALUE;
	return $_[0];

so it provides a way to chain method calls. But your custom handlers must handle that themselves.

=head1 NOTES

The (only) constructor for an object is the class' C<create> method, called from the base class' C<new> class method.

Note that for each property declaration there will be three new subroutines defined for the calling package. The first one was
just talked straight above; it's not new in the sense it will just occupy the place of the subroutine. Two others
will get names "get_$prop" and "set_$prop". So calling, for example, a name property of an object in any mode invokes C<< $obj->name >>
and that checks what accessor to call. You can foil read-write checks by calling the "get_$prop" or "set_$prop" methods directly.
Unless the class actually provides a non-implicit accessor for disabled access modes, this is probably not very useful.

There are no any measures to provide any scope restrictions, as the aim of the module to stay close to Perl's
simplistic object model. That is, everyone is encouraged to follow the public interface of a class, but if they
decide to open the black box up, it's alright. In line with this, the "get_$prop" or "set_$prop" methods are not hidden from
outside access.

No AUTOLOAD or other special Perl package methods are overriden by Object::Attributed and thus its descendants.

=head2 Inheritance

A subclass inherits all parent properties, their handlers and initializators. To override either of them, a new declaration
with the same name is required. To provide maximum flexibility, you are not prohibited from breaking any interface established
by a parent class. You can freely change access mode for properties, for instance. You can't override only a "set_$prop" or
"get_$prop" method to alter its behavior. A new declaration of the property that you are trying to override is due.

If calling a parent's method is required, the standart C<SUPER::> pseudo-package or direct parent name together
with method call should be used.

Constructors don't propagade forward to parents automatically. Therefore the usual thing you should do, after storing the C<$self>
reference, is to call the parent's constructor, with the same or different arguments. The constructor of base Object:Attributed
class does nothing, so in this or other similar cases it's not necessary. The C<Init> attribute is supported only for constructors;
Initializers don't run on subsequent calls to the constructor.

=head2 About the 'sub' in property declaration

It's used for several reasons. First, the module uses Attribute::Handlers, and it requires to either supply a Perl type
to filter others out, or accept all of them in attribute handlers. It didn't feel natural to me use the package in a way
that accepts everything but subs, as it should be naturally. So I did the opposite way, I handle the Prop and Init attributes
only on subroutines, with the reasoning behind that being that Object::Attributed transforms the sub declaring either
of the attributes into another, coming from the module. So the C<sub> keyword serves as a reminder to the programmer that
after Object::Attributed processes the attribute will still be a subroutine, albeit a different one.

=head1 ISSUES AND CONTACTS

For all issues you are welcome to use the Github bug tracking system. I can always be contacted there as well.

=cut

BEGIN
{
	push @Carp::CARP_NOT,'Attribute::Handlers';
}

use constant specifiers=>qw/read write name getter setter/;
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

my %init_lists=('Object::Attributed'=>{create=>{list=>[]}});

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
	no warnings 'redefine';
	*$symbol=sub
	{
		my @copy=@_;
		my $self=shift;
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
		#*$symbol=$code;
		goto &$code;
	} if $first_time;
}

package Object::Attributed::implicit_handlers;
# hides this from being inherited by subclasses and also allows to check the package later
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
