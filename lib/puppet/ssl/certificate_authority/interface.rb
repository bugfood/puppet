# This class is basically a hidden class that knows how to act
# on the CA.  It's only used by the 'puppetca' executable, and its
# job is to provide a CLI-like interface to the CA class.
class Puppet::SSL::CertificateAuthority::Interface
    INTERFACE_METHODS = [:destroy, :list, :revoke, :generate, :sign, :print, :verify]

    class InterfaceError < ArgumentError; end

    attr_reader :method, :subjects, :options

    # Actually perform the work.
    def apply(ca)
        unless subjects or method == :list
            raise ArgumentError, "You must provide hosts or :all when using %s" % method
        end

        begin
            if respond_to?(method)
                return send(method, ca)
            end

            (subjects == :all ? ca.list : subjects).each do |host|
                ca.send(method, host)
            end
        rescue InterfaceError
            raise
        rescue => detail
            puts detail.backtrace if Puppet[:trace]
            Puppet.err "Could not call %s: %s" % [method, detail]
        end
    end

    def generate(ca)
        raise InterfaceError, "It makes no sense to generate all hosts; you must specify a list" if subjects == :all

        subjects.each do |host|
            ca.generate(host, options)
        end
    end

#<<<<<<< HEAD
    #def initialize(method, subjects)
    #    self.method = method
    #    self.subjects = subjects
    #end
#=======
    def initialize(method, options)
        self.method = method
        self.subjects = options.delete(:to)
        @options = options
    end
#>>>>>>> b052c24... (#2848) CSR subjectAltNames handling while signing.

    # List the hosts.
    def list(ca)
        signed = ca.list
        requests = ca.waiting?

        case subjects
        when :all
            hosts = [signed, requests].flatten
        when :signed
            hosts = signed.flatten
        when nil
            hosts = requests
        else
            hosts = subjects
        end

        certs = {:signed => {}, :invalid => {}, :request => {}}

        return if hosts.empty?

        hosts.uniq.sort.each do |host|
            begin
                ca.verify(host) unless requests.include?(host)
            rescue Puppet::SSL::CertificateAuthority::CertificateVerificationError => details
                verify_error = details.to_s
            end

            if verify_error
                cert = Puppet::SSL::Certificate.indirection.find(host)
                certs[:invalid][host] = [cert, verify_error]
            elsif signed.include?(host)
                cert = Puppet::SSL::Certificate.indirection.find(host)
                certs[:signed][host] = cert
            else
                req = Puppet::SSL::CertificateRequest.indirection.find(host)
                certs[:request][host] = req
            end
        end

        names = certs.values.map(&:keys).flatten

        name_width = names.sort_by(&:length).last.length rescue 0

        output = [:request, :signed, :invalid].map do |type|
            next if certs[type].empty?

            certs[type].map do |host,info|
                format_host(ca, host, type, info, name_width)
            end
        end.flatten.compact.sort.join("\n")

        puts output
    end

    def format_host(ca, host, type, info, width)
        certish, verify_error = info
        alt_names = case type
                    when :signed
                        certish.subject_alt_names || []
                    when :request
                        certish.subject_alt_names || []
                    else
                        []
                    end

        alt_names.delete(host)

        alt_str = "(alt names: #{alt_names.join(', ')})" unless alt_names.empty?

        glyph = {:signed => '+', :request => ' ', :invalid => '-'}[type]

        name = host.ljust(width)
        explanation = "(#{verify_error})" if verify_error

        [glyph, name, alt_str, explanation].compact.join(' ')
    end

    # Set the method to apply.
    def method=(method)
        raise ArgumentError, "Invalid method %s to apply" % method unless INTERFACE_METHODS.include?(method)
        @method = method
    end

    # Print certificate information.
    def print(ca)
        (subjects == :all ? ca.list : subjects).each do |host|
            if value = ca.print(host)
                puts value
            else
                Puppet.err "Could not find certificate for %s" % host
            end
        end
    end

    # Sign a given certificate.
    def sign(ca)
        list = subjects == :all ? ca.waiting? : subjects
        raise InterfaceError, "No waiting certificate requests to sign" if list.empty?
        list.each do |host|
            ca.sign(host, options[:allow_dns_alt_names])
        end
    end

    # Set the list of hosts we're operating on.  Also supports keywords.
    def subjects=(value)
        unless value == :all or value == :signed or value.is_a?(Array)
            raise ArgumentError, "Subjects must be an array or :all; not %s" % value
        end

        if value.is_a?(Array) and value.empty?
            value = nil
        end

        @subjects = value
    end
end

