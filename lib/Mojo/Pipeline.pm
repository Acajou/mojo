# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Pipeline;

use strict;
use warnings;

use base 'Mojo::Transaction';

__PACKAGE__->attr(safe_post => 0);
__PACKAGE__->attr(active => sub { [] });
__PACKAGE__->attr(finished => sub { [] });

__PACKAGE__->attr('_all_written');
__PACKAGE__->attr([qw/_reader _writer/] => 0);

# No children have ever meddled with the Republican Party and lived to tell
# about it.
sub new {
    my $self = shift->SUPER::new();

    # Transactions
    $self->active([@_]);

    return $self;
}

sub client_info {
    my $self = shift;

    if (scalar @{$self->active}) {
        return $self->active->[-1]->client_info(@_);
    }
    elsif (scalar @{$self->finished}) {
        return $self->finished->[-1]->client_info(@_);
    }
    else {
        return undef;
    }
}

sub client_connect {
    my $self = shift;

    # Connect all
    $_->client_connect for @{$self->active};
    $self->state('connect');

    return $self;
}

sub client_connected {
    my $self = shift;

    # All connected
    for my $tx (@{$self->active}) {

        # Connected
        $tx->client_connected;

        # Meta information
        $tx->connection($self->connection);
        $tx->kept_alive($self->kept_alive);
        $tx->local_address($self->local_address);
        $tx->local_port($self->local_port);
        $tx->remote_address($self->remote_address);
        $tx->remote_port($self->remote_port);

    }
    $self->state('write_start_line');

    return $self;
}

sub client_get_chunk {
    my $self = shift;

    # Get chunk from current writer
    return $self->_current_writer->client_get_chunk;
}

sub client_read {
    my ($self, $chunk) = @_;

    # Read with current reader
    $self->_current_reader->client_read($chunk);

    # Transaction finished
    while ($self->_current_reader->is_finished) {

        push @{$self->finished}, shift @{$self->active};
        $self->_writer($self->_writer - 1) if $self->_writer;

        unless (scalar @{$self->active}) {

            # All done
            $self->_reader(0);
            $self->_writer(0);

            $self->done;
            return $self;
        }

        # Check for leftovers
        if (my $leftovers = $self->client_leftovers) {
            $self->_current_reader->client_read($leftovers);
        }
    }

    # Inherit state
    $self->_client_inherit_state;

    return $self;
}

sub client_leftovers {
    my $self = shift;

    # No previous reader
    return unless @{$self->finished};

    # Leftovers
    return $self->finished->[-1]->client_leftovers;
}

sub client_spin {
    my $self = shift;

    # Spin all
    $_->client_spin for @{$self->active};

    # Transaction finished
    my $writer = $self->_current_writer;
    if (!$self->_all_written && $writer->is_state('read_response')) {

        # All written
        $self->_all_written(1) unless $self->_next_writer;
    }

    # Inherit state
    $self->_client_inherit_state;

    return $self;
}

sub client_written {
    my ($self, $length) = @_;

    # Written
    $self->_current_writer->client_written($length);

    return $self;
}

sub continued { shift->active->[-1]->continued }

sub is_writing {
    my $self = shift;

    my $writing = $self->SUPER::is_writing;
    return $writing unless $self->safe_post;

    # If safe_post is on, don't write out a POST request until response from
    # previous request has been received
    # (This is even safer than rfc2616 (section 8.1.2.2), which suggests
    # waiting until the response status from the previous request has been
    # received)
    return
      if $writing
          && $self->_current_reader != $self->_current_writer
          && $self->_current_writer->req->method eq 'POST';

    return $writing;
}

sub keep_alive {
    my $self = shift;
    return $self->active->[$self->_writer]
      ? $self->active->[$self->_writer]->keep_alive(@_)
      : $self->finished->[-1]->keep_alive(@_);
}

sub req {
    my $self = shift;

    my @req;
    push @req, $_->req for @{$self->finished};
    push @req, $_->req for @{$self->active};
    return \@req;
}

sub res {
    my $self = shift;

    my @res;
    push @res, $_->res for @{$self->finished};
    push @res, $_->res for @{$self->active};
    return \@res;
}

sub server_accept {
    my ($self, $tx) = @_;

    # Meta information
    $tx->connection($self->connection);
    $tx->kept_alive($self->kept_alive);
    $tx->local_address($self->local_address);
    $tx->local_port($self->local_port);
    $tx->remote_address($self->remote_address);
    $tx->remote_port($self->remote_port);

    # Accept
    $tx->server_accept;
    push @{$self->active}, $tx;

    # Initialize
    $self->_reader($#{$self->active});

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_get_chunk {
    my $self = shift;

    # Get chunk from current writer
    return $self->_current_writer->server_get_chunk;
}

sub server_handled {
    my $self = shift;

    # Handled current reader
    $self->server_tx->server_handled;

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_leftovers {
    my $self = shift;

    # Last Transaction
    my $last = $self->active->[-1] if @{$self->active};
    $last = $self->finished->[-1] unless $last;

    # No leftovers
    return unless $last->req->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $last->req->leftovers;

    # Done
    $last->req->done;

    return $leftovers;
}

sub server_read {
    my $self = shift;

    # Request without a transaction
    unless ($self->_current_reader) {
        $self->error('Request without a transaction!');
        return $self;
    }

    # Normal request
    $self->_current_reader->server_read(@_);

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_spin {
    my $self = shift;

    # Spin all
    $_->server_spin for @{$self->active};

    # Next reader?
    my $reader = $self->_current_reader;
    if ($reader && $reader->req->is_finished) {
        $self->_next_reader
          unless $reader->is_state(qw/handle_request handle_continue/);
    }

    # Next writer
    if ($self->_current_writer->is_finished) {
        push @{$self->finished}, shift @{$self->active};
        $self->_reader($self->_reader - 1) if $self->_reader;
    }

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

# Current reader
sub server_tx { shift->_current_reader }

sub server_written {
    my $self = shift;

    # Written
    $self->_current_writer->server_written(@_);

    return $self;
}

sub transactions {
    my $self = shift;

    my @txs;
    push @txs, $_ for @{$self->finished};
    push @txs, $_ for @{$self->active};
    return \@txs;
}

# We are always in reading mode according to RFC, so writing has priority
sub _client_inherit_state {
    my $self = shift;

    # Inherit
    unless ($self->is_finished) {

        # State
        $self->state(
              $self->_all_written
            ? $self->_current_reader->state
            : $self->_current_writer->state
        );
        $self->state('read_response')
          if $self->is_state('done_with_leftovers');

        # Error
        $self->error('Transaction error.')
          if $self->_current_reader->has_error;
    }

    return $self;
}

sub _current_reader {
    my $self = shift;
    return $self->active->[$self->_reader];
}

sub _current_writer {
    my $self = shift;
    return $self->active->[$self->_writer];
}

sub _next_reader {
    my $self = shift;

    # Next
    $self->_reader($self->_reader + 1);

    # No reader
    return unless $self->active->[$self->_reader];

    # Found
    return 1;
}

sub _next_writer {
    my $self = shift;

    # Next
    $self->_writer($self->_writer + 1);

    # No writer
    return unless $self->active->[$self->_writer];

    # Found
    return 1;
}

# We are always in reading mode according to RFC, so writing has priority
sub _server_inherit_state {
    my $self = shift;

    # Handler first
    my $reader = $self->_current_reader;
    if ($reader && $reader->state =~ /^handle_/) {
        $self->state($reader->state);
        return $self;
    }

    # Inherit state
    $self->_current_writer
      ? $self->state($self->_current_writer->state)
      : $self->state('done');

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Pipeline - Pipelined HTTP Transaction Container

=head1 SYNOPSIS

    use Mojo::Pipeline;
    my $p = Mojo::Pipeline->new;

=head1 DESCRIPTION

L<Mojo::Pipeline> is a container for pipelined HTTP transactions.

=head1 ATTRIBUTES

L<Mojo::Pipeline> inherits all attributes from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<continued>

    my $continued = $p->continued;

=head2 C<keep_alive>

    my $keep_alive = $p->keep_alive;
    $p             = $p->keep_alive(1);

=head2 C<req>

    my $requests = $p->req;

=head2 C<res>

    my $responses = $p->res;

=head2 C<safe_post>

    my $safe_post = $p->safe_post;
    $p            = $p->safe_post(1);

=head2 C<transactions>

    my $transactions = $p->transactions;
    $p               = $p->transactions([Mojo::Transaction->new]);

=head1 METHODS

L<Mojo::Pipeline> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<new>

    my $p = Mojo::Pipeline->new;
    my $p = Mojo::Pipeline->new($tx1);
    my $p = Mojo::Pipeline->new($tx1, $tx2, $tx3);

=head2 C<client_connect>

    $p = $p->client_connect;

=head2 C<client_connected>

    $p = $p->client_connected;

=head2 C<client_get_chunk>

    my $chunk = $p->client_get_chunk;

=head2 C<client_info>

    my ($host, $port) = $p->client_info;

=head2 C<client_leftovers>

    my $leftovers = $p->client_leftovers;

=head2 C<client_read>

    $p = $p->client_read($chunk);

=head2 C<client_spin>

    $p = $p->client_spin;

=head2 C<client_written>

    $p = $p->client_written($length);

=head2 C<is_writing>

    my $writing = $p->is_writing;

=head2 C<server_accept>

    $p = $p->server_accept($tx);

=head2 C<server_get_chunk>

    my $chunk = $p->server_get_chunk;

=head2 C<server_handled>

    $p = $p->server_handled;

=head2 C<server_leftovers>

    my $leftovers = $p->server_leftovers;

=head2 C<server_read>

    $p = $p->server_read($chunk);

=head2 C<server_spin>

    $p = $p->server_spin;

=head2 C<server_tx>

    my $tx = $p->server_tx;

=head2 C<server_written>

    $p = $p->server_written($bytes);

=cut
