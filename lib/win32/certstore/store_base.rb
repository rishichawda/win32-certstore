#
# Author:: Piyush Awasthi (<piyush.awasthi@msystechnologies.com>)
# Copyright:: Copyright (c) 2017 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative "mixin/crypto"
require_relative "mixin/string"
require_relative "mixin/shell_out"
require_relative "mixin/unicode"
require "openssl"
require "json"

module Win32
  class Certstore
    module StoreBase
      include Win32::Certstore::Mixin::Crypto
      include Win32::Certstore::Mixin::Assertions
      include Win32::Certstore::Mixin::String
      include Win32::Certstore::Mixin::ShellOut
      include Win32::Certstore::Mixin::Unicode
      include Win32::Certstore::Mixin::Helper

      # Adding new certification in open certificate and return boolean
      # store_handler => Open certificate store handler
      # certificate_obj => certificate object must be in OpenSSL::X509
      def cert_add(store_handler, certificate_obj)
        validate_certificate_obj(certificate_obj)
        begin
          cert_args = cert_add_args(store_handler, certificate_obj)
          if CertAddEncodedCertificateToStore(*cert_args)
            true
          else
            lookup_error
          end
        rescue Exception => e
          lookup_error("add")
        end
      end

      # Get certificate from open certificate store and return certificate object
      # store_handler => Open certificate store handler
      # certificate_thumbprint => thumbprint is a hash. which could be sha1 or md5.
      def cert_get(store_handler, certificate_thumbprint)
        validate_thumbprint(certificate_thumbprint)
        thumbprint = update_thumbprint(certificate_thumbprint)
        cert_pem = get_cert_pem(thumbprint)
        unless cert_pem.empty?
          cert_pem = format_pem(cert_pem)
          build_openssl_obj(cert_pem)
        end
      end

      # Listing certificate of open certstore and return list in json
      def cert_list(store_handler)
        cert_name = memory_ptr
        cert_list = []
        begin
          while (pcert_context = CertEnumCertificatesInStore(store_handler, pcert_context)) && (not pcert_context.null?)
            cert_args = cert_get_name_args(pcert_context, cert_name)
            if CertGetNameStringW(*cert_args)
              cert_list << cert_name.read_wstring
            end
          end
          CertFreeCertificateContext(pcert_context)
        rescue Exception => e
          lookup_error("list")
        end
        cert_list.to_json
      end

      # Deleting certificate from open certificate store and return boolean
      # store_handler => Open certificate store handler
      # certificate_thumbprint => thumbprint is a hash. which could be sha1 or md5.
      def cert_delete(store_handler, certificate_thumbprint)
        begin
          if !certificate_name.empty? && (pcert_context = CertFindCertificateInStore(store_handler, X509_ASN_ENCODING, 0, CERT_FIND_ISSUER_STR, certificate_name.to_wstring, nil)) && (not pcert_context.null?)
            if CertDeleteCertificateFromStore(CertDuplicateCertificateContext(pcert_context))
              return "Deleted certificate #{certificate_name} successfully"
            else
              lookup_error
            end
          end
          return "Cannot find certificate with name as `#{certificate_name}`. Please re-verify certificate Issuer name or Friendly name"
        rescue Exception => e
          @error = "delete: "
          lookup_error
        end
      end

      private

      # Build arguments for CertAddEncodedCertificateToStore
      def cert_add_args(store_handler, certificate_obj)
        [store_handler, X509_ASN_ENCODING, der_cert(certificate_obj), certificate_obj.to_s.bytesize, 2, nil]
      end

      # Build argument for CertGetNameStringW
      def cert_get_name_args(pcert_context, cert_name)
        [pcert_context, CERT_NAME_FRIENDLY_DISPLAY_TYPE, CERT_NAME_ISSUER_FLAG, nil, cert_name, 1024]
      end

      # Remove extra space and : from thumbprint
      def update_thumbprint(certificate_thumbprint)
        certificate_thumbprint.gsub(/[^A-Za-z0-9]/, '')
      end

      # Convert OpenSSL::X509::Certificate object in .der formate
      def der_cert(cert_obj)
        FFI::MemoryPointer.from_string(cert_obj.to_der)
      end

      # Get certificate pem
      def get_cert_pem(thumbprint)
        IO::popen(["powershell.exe", cert_ps_cmd(thumbprint)]) {|io| io.readlines}
      end

      # Format pem
      def format_pem(cert_pem)
        cert_pem.join
      end

      # Build pem to OpenSSL::X509::Certificate object
      def build_openssl_obj(cert_pem)
        OpenSSL::X509::Certificate.new cert_pem
      end
      # Create empty memory pointer
      def memory_ptr
        FFI::MemoryPointer.new(2, 128)
      end
    end
  end
end
