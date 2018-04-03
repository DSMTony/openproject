require 'spec_helper'
require 'features/work_packages/work_packages_page'
require 'features/work_packages/details/inplace_editor/shared_examples'

describe 'custom field inplace editor', js: true do
  let(:user) { FactoryGirl.create :admin }
  let(:type) { FactoryGirl.create(:type_standard, custom_fields: custom_fields) }
  let(:project) {
    FactoryGirl.create :project,
                       types: [type],
                       work_package_custom_fields: custom_fields
  }
  let(:custom_fields) { [custom_field] }
  let(:work_package) {
    FactoryGirl.create :work_package,
                       type: type,
                       project: project,
                       custom_values: initial_custom_values
  }
  let(:wp_page) { Pages::SplitWorkPackage.new(work_package) }

  let(:property_name) { "customField#{custom_field.id}" }
  let(:field) { wp_page.edit_field(property_name) }

  before do
    login_as(user)

    wp_page.visit!
    wp_page.ensure_page_loaded
  end

  def expect_update(value, update_args)
    wp_field = update_args.delete(:field) { field }

    wp_field.set_value value
    wp_field.submit_by_enter if wp_field.field_type == 'input'
    wp_page.expect_notification(update_args)
    wp_page.dismiss_notification!
  end

  describe 'long text' do
    let(:custom_field) {
      FactoryGirl.create(:text_issue_custom_field, name: 'LongText')
    }
    let(:field) { WorkPackageEditorField.new wp_page, property_name }
    let(:initial_custom_values) { { custom_field.id => 'foo' } }

    it 'can cancel through the button only' do
      # Activate the field
      field.activate!

      # Pressing escape does nothing here
      field.cancel_by_escape
      field.expect_active!

      # Cancelling through the action panel
      field.cancel_by_click
      field.expect_inactive!
    end

    it_behaves_like 'a previewable field'
    it_behaves_like 'a workpackage autocomplete field'
  end

  describe 'custom field lists' do
    let(:custom_field1) {
      FactoryGirl.create(:list_wp_custom_field,
                        is_required: false,
                        possible_values: %w(foo bar baz))
    }
    let(:custom_field2) {
      FactoryGirl.create(:list_wp_custom_field,
                        is_required: false,
                        possible_values: %w(X Y Z))
    }

    let(:custom_fields) { [custom_field1, custom_field2] }
    let(:field1) {
      f = wp_page.custom_edit_field(custom_field1)
      f.field_type = 'select'
      f
    }
    let(:field2) {
      f = wp_page.custom_edit_field(custom_field2)
      f.field_type = 'select'
      f
    }
    let(:initial_custom_values) { {} }

    def custom_value(value)
      CustomOption.find_by(value: value).try(:id)
    end

    it 'properly updates both values' do
      field1.activate!
      expect_update 'bar',
                    message: I18n.t('js.notice_successful_update'),
                    field: field1

      field2.activate!
      expect_update 'Y',
                    message: I18n.t('js.notice_successful_update'),
                    field: field2

      wp_page.expect_attributes :"customField#{custom_field1.id}" => 'bar',
                                :"customField#{custom_field2.id}" => 'Y'

      field1.activate!
      field1.expect_value("/api/v3/custom_options/#{custom_value('bar')}")
      field1.cancel_by_escape

      field2.activate!
      field2.expect_value("/api/v3/custom_options/#{custom_value('Y')}")
      expect_update 'X',
                    message: I18n.t('js.notice_successful_update'),
                    field: field2

      wp_page.expect_attributes :"customField#{custom_field1.id}" => 'bar',
                                :"customField#{custom_field2.id}" => 'X'

    end
  end

  describe 'integer type' do
    let(:custom_field) {
      FactoryGirl.create(:integer_issue_custom_field, args.merge(name: 'MyNumber'))
    }
    let(:initial_custom_values) { { custom_field.id => 123 } }

    context 'with length restrictions' do
      let(:args) {
        { min_length: 2, max_length: 5 }
      }

      it 'renders errors for invalid entries' do
        field.activate!
        # exceeding max length
        expect_update '123456',
                      type: :error,
                      message: 'MyNumber is too long (maximum is 5 characters).'

        # below min length
        expect_update '1',
                      type: :error,
                      message: 'MyNumber is too short (minimum is 2 characters).'

        # Correct value
        expect_update '9999',
                      message: I18n.t('js.notice_successful_update')
        wp_page.expect_attributes property_name => '9999'
      end
    end

    context 'no restrictions' do
      let(:args) { {} }
      it 'renders errors for invalid entries' do
        # Valid input
        field.activate!
        expect_update '9999999999',
                      message: I18n.t('js.notice_successful_update')
        wp_page.expect_attributes property_name => '9999999999'

        # Remove value
        field.activate!
        expect_update '',
                      message: I18n.t('js.notice_successful_update')
        wp_page.expect_attributes property_name => '-'

        # Zero value
        field.activate_edition
        expect_update '0',
                      message: I18n.t('js.notice_successful_update')
        wp_page.expect_attributes property_name => '0'
      end
    end

    context 'required' do
      let(:args) { { is_required: true } }

      it 'renders errors for invalid entries' do
        # Invalid input (non-digit)
        field.activate!
        field.set_value ''
        field.expect_invalid

        expect(WorkPackages::UpdateService).not_to receive(:new)
        field.save!
      end
    end
  end


  describe 'float type' do
    let(:custom_field) {
      FactoryGirl.create(:float_wp_custom_field, args.merge(name: 'MyFloat'))
    }
    let(:args) { {} }
    let(:initial_custom_values) { { custom_field.id => 123.50 } }

    context 'with english locale' do
      let(:user) { FactoryGirl.create :admin, language: 'en' }

      it 'displays the float with english locale and allows editing' do
        field.expect_state_text '123.5'
        field.update '10000.55'
        field.expect_state_text '10,000.55'

        work_package.reload
        expect(work_package.custom_value_for(custom_field.id).typed_value).to eq 10000.55
      end
    end

    context 'with german locale' do
      let(:user) { FactoryGirl.create :admin, language: 'de' }

      it 'displays the float with german locale and allows editing' do
        field.expect_state_text '123,5'
        field.update '10000,55'
        field.expect_state_text '10.000,55'

        work_package.reload
        expect(work_package.custom_value_for(custom_field.id).typed_value).to eq 10000.55
      end
    end
  end
end
