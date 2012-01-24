require 'spec_helper'

describe User do
  it { should have_many(:user_repositories) }
  it { should have_many(:repositories).through(:user_repositories) }
  it { should have_many(:invoices) }
  it { should have_one(:credit_card) }
  it { should belong_to(:plan) }

  context "#create" do
    before do
      @free_plan = Factory(:plan, amount: 0)
      @paid_plan = Factory(:plan, amount: 1000)
    end
    subject { Factory(:user) }

    it "should have a free plan by default" do
      subject.plan.free?
    end
  end

  context "aasm_state" do
    subject { Factory(:user) }
    its(:aasm_state) { should == "unpaid" }

    context "#pay!" do
      before do
        invoice = Factory(:invoice, :user => subject)
        subject.expects(:notify_user_pay)
        subject.pay!
      end
      its(:aasm_state) { should == "paid" }

      it "should allow pay! more than once" do
        subject.stubs(:notify_user_pay)
        subject.pay!
        lambda { subject.pay! }.should_not raise_error
      end
    end

    context "#unpay!" do
      before do
        subject.stubs(:notify_user_pay)
        subject.pay!
        subject.expects(:notify_user_unpay)
        subject.unpay!
      end
      its(:aasm_state) { should == "unpaid" }
    end

    context "#trial!" do
      before do
        subject.trial!
      end
      its(:aasm_state) { should == "trial" }
    end
  end

  context "#update_plan" do
    subject { Factory(:user, stripe_customer_token: "123456") }
    let(:free_plan) { Factory(:plan, amount: 0, trial_period_days: 0, name: "Free", identifier: "free") }
    let(:basic_plan) { Factory(:plan, amount: 500, trial_period_days: 7, name: "Basic", identifier: "basic") }

    context "free to basic" do
      before do
        subject.update_attribute(:plan, free_plan)
        customer = mock
        Stripe::Customer.expects(:retrieve).with("123456").returns(customer)
        customer.expects(:update_subscription).with(plan: "basic")
        subject.update_plan(basic_plan)
      end
      its(:aasm_state) { should == "trial" }
      it "should be basic plan" do
        subject.plan == basic_plan
      end
    end

    context "basic to free" do
      before do
        subject.update_attribute(:plan, basic_plan)
        subject.trial!
        customer = mock
        Stripe::Customer.expects(:retrieve).with("123456").returns(customer)
        customer.expects(:update_subscription).with(plan: "free")
        subject.update_plan(free_plan)
      end
      its(:aasm_state) { should == "unpaid" }
      it "should be free plan" do
        subject.plan == free_plan
      end
    end
  end

  context "#add_repository" do
    before do
      Repository.any_instance.stubs(:set_privacy)
      Repository.any_instance.stubs(:sync_github)
      @user = Factory(:user, nickname: "flyerhzm", github_uid: 66836)
      @repository = Factory(:repository, github_name: "flyerhzm/old")
      @user.repositories << @repository
    end

    it "should create a new repository within his own account" do
      lambda { @user.add_repository("flyerhzm/new") }.should change(@user.repositories, :count).by(1)
    end

    it "should create a new repository when he is a collaborator" do
      collaborators = File.read(Rails.root.join("spec/fixtures/collaborators.json").to_s)
      stub_request(:get, "https://api.github.com/repos/railsbp/railsbp.com/collaborators").to_return(body: collaborators)
      lambda { @user.add_repository("railsbp/railsbp.com") }.should change(@user.repositories, :count).by(1)
    end

    it "should not create a new repository when he don't have privilege" do
      stub_request(:get, "https://api.github.com/repos/test/test.com/collaborators").to_return(body: "[]")
      lambda { @user.add_repository("test/test.com") }.should raise_exception(AuthorizationException)
    end

    it "should attach to an old repository" do
      lambda { @user.add_repository("flyerhzm/old") }.should_not change(@user.repositories, :count)
    end
  end

  context "#fakemail?" do
    context "flyerhzm" do
      subject { Factory(:user, email: "flyerhzm@gmail.com") }
      its(:fakemail?) { should be_false }
    end
    context "flyerhzm-test" do
      subject { Factory(:user, email: "flyerhzm-test@fakemail.com") }
      its(:fakemail?) { should be_true }
    end
  end

  context "#notify_user_pay" do
    context "fakemail" do
      it "should not send mail" do
        user = Factory(:user, email: "test@fakemail.com")
        UserMailer.expects(:delay).never
        user.notify_user_pay
      end
    end
  end

  context "#notify_user_pay_failed" do
    context "fakemail" do
      it "should not send mail" do
        user = Factory(:user, email: "test@fakemail.com")
        UserMailer.expects(:delay).never
        user.notify_user_pay_failed
      end
    end
  end

  context "#notify_user_unpay" do
    context "fakemail" do
      it "should not send mail" do
        user = Factory(:user, email: "test@fakemail.com")
        UserMailer.expects(:delay).never
        user.notify_user_unpay
      end
    end
  end

  context "allow_privacy?" do
    context "public_plan" do
      let(:public_plan) { Factory(:plan, allow_privacy: false) }
      subject { Factory(:user).tap { |user| user.update_attribute(:plan, public_plan) } }
      its(:allow_privacy?) { should == false }
    end

    context "privcate_plan" do
      let(:private_plan) { Factory(:plan, allow_privacy: true) }
      subject { Factory(:user).tap { |user| user.update_attribute(:plan, private_plan) } }
      its(:allow_privacy?) { should == true }
    end
  end
end
