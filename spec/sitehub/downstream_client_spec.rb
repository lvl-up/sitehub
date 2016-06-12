require 'sitehub/downstream_client'

class SiteHub
  describe DownstreamClient do
    include_context :http_proxy_rules

    let(:current_version_url) { 'http://127.0.0.1:10111' }
    let(:mapped_path) { '/path' }

    let(:app) do
      described_class.new(url: current_version_url,
                          mapped_path: mapped_path)
    end

    describe '#call' do
      context 'downstream request' do
        before do
          stub_request(:get, current_version_url).to_return(body: 'body')
        end

        it 'preserves the body when forwarding request' do
          body = { 'key' => 'value' }
          stub_request(:put, current_version_url).with(body: body)
          put(mapped_path, body)
        end

        it 'preserves the headers when forwarding request' do
          get(mapped_path, '', 'HTTP_HEADER' => 'value')
          assert_requested :get, current_version_url, headers: { 'Header' => 'value' }
        end

        it_behaves_like 'prohibited_header_filter' do
          include_context :rack_headers

          subject do
            http_headers = prohibited_headers.merge(permitted_header => 'value')
            get(mapped_path, {}, to_rack_headers(http_headers))
            WebMock::RequestRegistry.instance.requested_signatures.hash.keys.first.headers
          end
        end

        context 'headers' do
          # used to identify the originally requested host
          context 'x-forwarded-host header' do
            context 'header not present' do
              it 'assigns it to the requested host' do
                get(mapped_path, {})
                assert_requested :get, current_version_url, headers: { 'X-FORWARDED-HOST' => 'example.org' }
              end
            end

            context 'header already present' do
              it 'appends the host to the existing value' do
                get(mapped_path, {}, 'HTTP_X_FORWARDED_HOST' => 'first.host,second.host')
                assert_requested :get, current_version_url,
                                 headers: { 'X-FORWARDED-HOST' => 'first.host,second.host,example.org' }
              end
            end
          end

          # used for identifying the originating IP address of a request.
          context 'x-forwarded-for' do
            context 'header not present' do
              it 'introduces it assigned to the value the remote-addr http header' do
                x_forwarded_for_header = Constants::HttpHeaderKeys::X_FORWARDED_FOR_HEADER
                get(mapped_path)
                expected_headers = { x_forwarded_for_header => last_request.env['REMOTE_ADDR'] }
                assert_requested :get, current_version_url, headers: expected_headers
              end
            end

            context 'already present' do
              it 'appends the value of the remote-addr header to it' do
                x_forwarded_for_header = Constants::RackHttpHeaderKeys::X_FORWARDED_FOR
                get(mapped_path, {}, x_forwarded_for_header => 'first_host_ip')
                expected_header_value = "first_host_ip,#{last_request.env['REMOTE_ADDR']}"
                expected_headers = { Constants::HttpHeaderKeys::X_FORWARDED_FOR_HEADER => expected_header_value }
                assert_requested :get, current_version_url, headers: expected_headers
              end
            end
          end
        end
      end

      context 'response' do
        include_context :http_proxy_rules

        it 'passes request mapping information in to the environment hash' do
          expected_mapping = RequestMapping.new(source_url: "http://example.org#{mapped_path}",
                                                mapped_url: current_version_url,
                                                mapped_path: mapped_path)

          stub_request(:get, current_version_url)
          get(mapped_path, {})
          expect(last_request.env[REQUEST_MAPPING]).to eq(expected_mapping)
        end
      end
    end
  end
end