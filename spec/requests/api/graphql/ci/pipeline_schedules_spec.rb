# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project.pipelineSchedules' do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, :public, creator: user, namespace: user.namespace) }
  let_it_be(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project, owner: user) }

  let(:pipeline_schedule_graphql_data) { graphql_data_at(:project, :pipeline_schedules, :nodes, 0) }

  let(:params) { {} }

  let(:fields) do
    <<~QUERY
      nodes {
        id
        description
        active
        nextRunAt
        realNextRun
        lastPipeline {
             id
        }
        refForDisplay
        refPath
        forTag
        cron
        cronTimezone
        editPath
      }
    QUERY
  end

  let(:query) do
    %(
      query {
        project(fullPath: "#{project.full_path}") {
          pipelineSchedules {
            #{fields}
          }
        }
      }
    )
  end

  describe 'computed graphql fields' do
    before do
      pipeline_schedule.pipelines << build(:ci_pipeline, project: project)

      post_graphql(query, current_user: user)
    end

    it_behaves_like 'a working graphql query'

    it 'returns calculated fields for a pipeline schedule' do
      ref_for_display = pipeline_schedule_graphql_data['refForDisplay']

      expect(ref_for_display).to eq('master')
      expect(pipeline_schedule_graphql_data['refPath']).to eq("/#{project.full_path}/-/commits/#{ref_for_display}")
      expect(pipeline_schedule_graphql_data['forTag']).to be(false)
    end

    it 'returns the edit_path for a pipeline schedule' do
      edit_path = pipeline_schedule_graphql_data['editPath']

      expect(edit_path).to eq("/#{project.full_path}/-/pipeline_schedules/#{pipeline_schedule.id}/edit")
    end
  end

  describe 'permissions' do
    let_it_be(:another_user) { create(:user) }

    before do
      post_graphql(query, current_user: another_user)
    end

    it 'does not return the edit_path for a pipeline schedule for a user that does not have permissions' do
      edit_path = pipeline_schedule_graphql_data['editPath']

      expect(edit_path).to be nil
    end
  end

  it 'avoids N+1 queries' do
    create_pipeline_schedules(1)

    control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }

    create_pipeline_schedules(3)

    action = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }

    expect(action).not_to exceed_query_limit(control)
  end

  def create_pipeline_schedules(count)
    create_list(:ci_pipeline_schedule, count, project: project)
      .each do |pipeline_schedule|
      create(:user).tap do |user|
        project.add_developer(user)
        pipeline_schedule.update!(owner: user)
      end
      pipeline_schedule.pipelines << build(:ci_pipeline, project: project)
    end
  end
end
