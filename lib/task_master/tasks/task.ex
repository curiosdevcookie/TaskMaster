defmodule TaskMaster.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field :priority, Ecto.Enum, values: [:low, :medium, :high], default: :medium
    field :status, Ecto.Enum, values: [:open, :progressing, :completed], default: :open
    field :description, :string
    field :title, :string
    field :due_date, :date
    field :duration, :integer
    field :completed_at, :naive_datetime
    field :indoor, :boolean, default: false

    belongs_to :creator, TaskMaster.Accounts.User, foreign_key: :created_by
    belongs_to :parent_task, TaskMaster.Tasks.Task, foreign_key: :parent_task_id

    has_many :task_participations, TaskMaster.Tasks.TaskParticipation
    has_many :participants, through: [:task_participations, :user]

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :due_date,
      :status,
      :duration,
      :priority,
      :indoor,
      :created_by,
      :parent_task_id
    ])
    |> cast_assoc(:task_participations, with: &TaskMaster.Tasks.TaskParticipation.changeset/2)
    |> validate_required([
      :title,
      :status,
      :priority,
      :indoor
    ])
    |> unique_constraint(:title, name: :tasks_title_index)
  end
end
