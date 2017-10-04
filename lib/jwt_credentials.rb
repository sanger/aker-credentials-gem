require 'jwt'
require 'ostruct'
require 'request_store'
require 'jwt_serializer'

module JWTCredentials

  def self.included(base)
    base.instance_eval do |klass|
      before_action :check_credentials
      before_action :apply_credentials
    end
  end

  attr_reader :x_auth_user

  def current_user
    if respond_to?(:auth_user)
      auth_user || x_auth_user
    else
      x_auth_user
    end
  end

  def apply_credentials
    RequestStore.store[:x_authorisation] = current_user
  end

  def build_user(hash)
    if defined? User
      @x_auth_user = User.from_jwt_data(hash)
    else
      @x_auth_user = OpenStruct.new(hash)
    end
  end

  def check_credentials
    @x_auth_user = nil
    # JWT present in header (microservices or current SSO)
    if request.headers.to_h['HTTP_X_AUTHORISATION']
      begin
        user_from_jwt(request.headers.to_h['HTTP_X_AUTHORISATION'])
      rescue JWT::VerificationError => e
        render body: nil, status: :unauthorized
      rescue JWT::ExpiredSignature => e
        render body: nil, status: :unauthorized
      end
    # JWT present in cookie (front-end services aka new SSO)
    elsif cookies[:aker_user]
      begin
        user_from_jwt(cookies[:aker_user])
      rescue JWT::VerificationError => e
        # Potential hacking attempt so log this?
        render body: "JWT in cookie, VerificationError", status: :unauthorized
      rescue JWT::ExpiredSignature => e
        # This should refresh token?
        render body: "JWT from cookie has expired", status: :unauthorized
      end
    # Fake JWT User for development
    elsif Rails.configuration.respond_to? :default_jwt_user
      build_user(Rails.configuration.default_jwt_user)
    end
  end

  def jwt_provided?
    x_auth_user.present?
  end

  def user_from_jwt(jwt_container)
    secret_key = Rails.configuration.jwt_secret_key
    payload, header = JWT.decode jwt_container, secret_key, true, { algorithm: 'HS256'}
    build_user(payload["data"])
  end
end
