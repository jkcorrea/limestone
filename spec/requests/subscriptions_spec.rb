# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionsController, type: :request do
  let(:product) { create(:product) }
  let(:plan) { create(:plan, product: product) }
  let(:plan_annual) { create(:plan, :basic_annual, product: product) }

  let(:product_pro) { create(:product, :pro) }
  let(:plan_pro) { create(:plan, :pro_monthly, product: product_pro) }

  let(:user_trial) { create(:user) }
  let(:user_subscribed) { create(:user, :trial_expired) }

  let(:payment_method) do
    Stripe::PaymentMethod.create({
      type: "card",
      card: {
        number: "4242424242424242",
        exp_month: 6,
        exp_year: 2025,
        cvc: "123",
      },
    })
  end

  before do
    user_subscribed.processor = "stripe"
    stripe_plan = Stripe::Plan.retrieve(plan.stripe_id)
    # NOTE We don't need a card token here because the plan has a trial.
    # If plan has no trial, then a card token is required.
    user_subscribed.subscribe(name: product.name, plan: stripe_plan.id)
  end

  describe "GET billing_path" do
    subject do
      get billing_path
      response
    end

    context "as a trial user" do
      before { sign_in user_trial }

      it "redirects to subscribe page" do
        expect(subject).to redirect_to subscribe_path
      end
    end

    context "as a subscribed user" do
      before { sign_in user_subscribed }

      it "renders subscriptions/show" do
        expect(subject).to have_http_status(:success)
        expect(subject).to render_template "subscriptions/show"
      end
    end
  end

  describe "PATCH /subscriptions" do
    let(:payment_method_dbl) { double Stripe::PaymentMethod }
    let(:customer_dbl) { double Stripe::Customer }

    context "update card" do
      subject do
        patch subscriptions_path, params: {
          payment_method_id: payment_method.id,
          card_brand: "MasterCard",
          card_exp_month: 6,
          card_exp_year: 2025,
          card_last4: 4242
        }
        response
      end

      context "as a subscribed user" do
        before { sign_in user_subscribed }
        it "updates card" do
          expect(subject).to redirect_to billing_path
          expect(flash[:success]).to match "Subscription updated"
          expect(user_subscribed.card_last4).to eq "4242"
        end
      end
    end

    context "swap products" do
      before { sign_in user_subscribed }
      subject do
        patch subscriptions_path, params: {
          plan_id: plan_pro.id
        }
      end

      it "swaps the product and plan" do
        expect(user_subscribed.get_subscription.processor_plan).to eq plan.stripe_id
        stripe_subscription = Stripe::Subscription.retrieve(user_subscribed.get_subscription.processor_id)
        expect(stripe_subscription.plan.product).to eq product.stripe_id

        expect(subject).to redirect_to billing_path

        stripe_subscription = Stripe::Subscription.retrieve(user_subscribed.get_subscription.processor_id)
        expect(stripe_subscription.plan.product).to eq product_pro.stripe_id
        expect(flash[:success]).to match "Subscription updated"
        expect(user_subscribed.get_subscription.processor_plan).to eq plan_pro.stripe_id
        expect(user_subscribed.plan_id).to eq plan_pro.id
      end
    end

    context "swap plans" do
      before { sign_in user_subscribed }
      subject do
        patch subscriptions_path, params: {
          plan_id: plan_annual.id
        }
      end

      it "swaps the plan and keeps the product" do
        expect(user_subscribed.get_subscription.processor_plan).to eq plan.stripe_id
        stripe_subscription = Stripe::Subscription.retrieve(user_subscribed.get_subscription.processor_id)
        expect(stripe_subscription.plan.product).to eq product.stripe_id

        expect(subject).to redirect_to billing_path

        stripe_subscription = Stripe::Subscription.retrieve(user_subscribed.get_subscription.processor_id)
        expect(stripe_subscription.plan.product).to eq product.stripe_id
        expect(flash[:success]).to match "Subscription updated"
        expect(user_subscribed.get_subscription.processor_plan).to eq plan_annual.stripe_id
        expect(user_subscribed.plan_id).to eq plan_annual.id
      end
    end
  end
end
