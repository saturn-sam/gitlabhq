# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Internal::MailRoom do
  let(:base_configs) do
    {
      enabled: true,
      address: 'address@example.com',
      port: 143,
      ssl: false,
      start_tls: false,
      mailbox: 'inbox',
      idle_timeout: 60,
      log_path: Rails.root.join('log', 'mail_room_json.log').to_s,
      expunge_deleted: false
    }
  end

  let(:enabled_configs) do
    {
      incoming_email: base_configs.merge(
        secure_file: Rails.root.join('tmp', 'tests', '.incoming_email_secret').to_s
      ),
      service_desk_email: base_configs.merge(
        secure_file: Rails.root.join('tmp', 'tests', '.service_desk_email').to_s
      )
    }
  end

  let(:auth_payload) { { 'iss' => Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_JWT_ISSUER, 'iat' => (Time.now - 10.seconds).to_i } }

  let(:incoming_email_secret) { 'incoming_email_secret' }
  let(:service_desk_email_secret) { 'service_desk_email_secret' }

  let(:email_content) { fixture_file("emails/commands_in_reply.eml") }

  before do
    allow(Gitlab::MailRoom::Authenticator).to receive(:secret).with(:incoming_email).and_return(incoming_email_secret)
    allow(Gitlab::MailRoom::Authenticator).to receive(:secret).with(:service_desk_email).and_return(service_desk_email_secret)
    allow(Gitlab::MailRoom).to receive(:enabled_configs).and_return(enabled_configs)
  end

  around do |example|
    freeze_time do
      example.run
    end
  end

  describe "POST /internal/mail_room/*mailbox_type" do
    context 'handle incoming_email successfully' do
      let(:auth_headers) do
        jwt_token = JWT.encode(auth_payload, incoming_email_secret, 'HS256')
        { Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_HEADER => jwt_token }
      end

      it 'schedules a EmailReceiverWorker job with raw email content' do
        Sidekiq::Testing.fake! do
          expect do
            post api("/internal/mail_room/incoming_email"), headers: auth_headers, params: email_content
          end.to change { EmailReceiverWorker.jobs.size }.by(1)
        end

        expect(response).to have_gitlab_http_status(:ok)

        job = EmailReceiverWorker.jobs.last
        expect(job).to match a_hash_including('args' => [email_content])
      end
    end

    context 'handle service_desk_email successfully' do
      let(:auth_headers) do
        jwt_token = JWT.encode(auth_payload, service_desk_email_secret, 'HS256')
        { Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_HEADER => jwt_token }
      end

      it 'schedules a ServiceDeskEmailReceiverWorker job with raw email content' do
        Sidekiq::Testing.fake! do
          expect do
            post api("/internal/mail_room/service_desk_email"), headers: auth_headers, params: email_content
          end.to change { ServiceDeskEmailReceiverWorker.jobs.size }.by(1)
        end

        expect(response).to have_gitlab_http_status(:ok)

        job = ServiceDeskEmailReceiverWorker.jobs.last
        expect(job).to match a_hash_including('args' => [email_content])
      end
    end

    context 'email content exceeds limit' do
      let(:auth_headers) do
        jwt_token = JWT.encode(auth_payload, incoming_email_secret, 'HS256')
        { Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_HEADER => jwt_token }
      end

      before do
        allow(EmailReceiverWorker).to receive(:perform_async).and_raise(
          Gitlab::SidekiqMiddleware::SizeLimiter::ExceedLimitError.new(EmailReceiverWorker, email_content.bytesize, email_content.bytesize - 1)
        )
      end

      it 'responds with 400 bad request' do
        Sidekiq::Testing.fake! do
          expect do
            post api("/internal/mail_room/incoming_email"), headers: auth_headers, params: email_content
          end.not_to change { EmailReceiverWorker.jobs.size }
        end

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(Gitlab::Json.parse(response.body)).to match a_hash_including(
          { "success" => false, "message" => "EmailReceiverWorker job exceeds payload size limit" }
        )
      end
    end

    context 'not authenticated' do
      it 'responds with 401 Unauthorized' do
        post api("/internal/mail_room/incoming_email")

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'wrong token authentication' do
      let(:auth_headers) do
        jwt_token = JWT.encode(auth_payload, 'wrongsecret', 'HS256')
        { Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_HEADER => jwt_token }
      end

      it 'responds with 401 Unauthorized' do
        post api("/internal/mail_room/incoming_email"), headers: auth_headers

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'wrong mailbox type authentication' do
      let(:auth_headers) do
        jwt_token = JWT.encode(auth_payload, service_desk_email_secret, 'HS256')
        { Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_HEADER => jwt_token }
      end

      it 'responds with 401 Unauthorized' do
        post api("/internal/mail_room/incoming_email"), headers: auth_headers

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'not supported mailbox type' do
      let(:auth_headers) do
        jwt_token = JWT.encode(auth_payload, incoming_email_secret, 'HS256')
        { Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_HEADER => jwt_token }
      end

      it 'responds with 401 Unauthorized' do
        post api("/internal/mail_room/invalid_mailbox_type"), headers: auth_headers

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'not enabled mailbox type' do
      let(:enabled_configs) do
        {
          incoming_email: base_configs.merge(
            secure_file: Rails.root.join('tmp', 'tests', '.incoming_email_secret').to_s
          )
        }
      end

      let(:auth_headers) do
        jwt_token = JWT.encode(auth_payload, service_desk_email_secret, 'HS256')
        { Gitlab::MailRoom::Authenticator::INTERNAL_API_REQUEST_HEADER => jwt_token }
      end

      it 'responds with 401 Unauthorized' do
        post api("/internal/mail_room/service_desk_email"), headers: auth_headers

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end
  end
end
