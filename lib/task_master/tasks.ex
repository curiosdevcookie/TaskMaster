defmodule TaskMaster.Tasks do
  @moduledoc """
  The Tasks context.
  """

  import Ecto.Query, warn: false
  alias TaskMaster.Repo

  alias TaskMaster.Tasks.Task
  alias TaskMaster.Tasks.TaskParticipation

  @doc """
  Returns the list of tasks.

  ## Examples

      iex> list_tasks()
      [%Task{}, ...]

  """
  def list_tasks(org_id) do
    Task
    |> Task.for_org(org_id)
    |> Repo.all()
    |> Repo.preload([:task_participations, :participants])
  end

  def list_parent_tasks(org_id) do
    Task
    |> Task.for_org(org_id)
    |> where([t], is_nil(t.parent_task_id))
    |> Repo.all()
    |> Repo.preload([:task_participations, :participants])
  end

  def list_subtasks(org_id) do
    Task
    |> Task.for_org(org_id)
    |> where([t], not is_nil(t.parent_task_id))
    |> Repo.all()
    |> Repo.preload([:task_participations, :participants])
  end

  def get_task!(id, _org_id) when is_nil(id), do: %Task{}

  def get_task!(id, org_id) do
    Task
    |> Task.for_org(org_id)
    |> Repo.get!(id)
    |> Repo.preload([:task_participations, :participants])
  end

  def create_task(attrs \\ %{}, participants \\ [], org_id, parent_id \\ nil) do
    attrs = Map.merge(attrs, %{"parent_task_id" => parent_id})

    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, task} ->
        task = add_participants(task, participants, org_id)
        task = Repo.preload(task, :participants)
        updated_parent_task = update_parent_task_duration(task)
        broadcast({:ok, updated_parent_task}, :task_created)
        {:ok, task}

      error ->
        error
    end
  end

  def update_task(%Task{} = task, attrs, participants \\ [], org_id) do
    do_update_task(task, attrs, participants, org_id)
  end

  defp do_update_task(task, attrs, participants, org_id) do
    attrs = maybe_set_completed_at(attrs, task)

    task
    |> Task.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_task} ->
        updated_task = update_participants(updated_task, participants, org_id)
        updated_task = Repo.preload(updated_task, :participants)
        update_parent_task_duration(updated_task)
        {:ok, parent_updated_task} = maybe_update_parent_task(updated_task)
        broadcast({:ok, parent_updated_task}, :task_updated)
        {:ok, updated_task}
        broadcast({:ok, updated_task}, :task_updated)

      error ->
        error
    end
  end

  defp update_parent_task_duration(%Task{parent_task_id: nil} = task), do: task

  defp update_parent_task_duration(%Task{parent_task_id: parent_id} = task) do
    parent_task = get_task!(parent_id, task.organization_id)
    subtasks_duration = calculate_subtasks_duration(parent_id)

    do_update_task(parent_task, %{duration: subtasks_duration}, [], task.organization_id)
  end

  defp calculate_subtasks_duration(parent_task_id) do
    from(t in Task,
      where: t.parent_task_id == ^parent_task_id and t.status != :completed,
      select: sum(t.duration)
    )
    |> Repo.one()
  end

  defp get_parent_task_status(parent_id) do
    subtasks = from(t in Task, where: t.parent_task_id == ^parent_id) |> Repo.all()

    cond do
      Enum.all?(subtasks, &(&1.status == :completed)) -> :completed
      Enum.any?(subtasks, &(&1.status == :completed)) -> :progressing
      true -> :open
    end
  end

  defp maybe_update_parent_task(%Task{parent_task_id: nil} = task), do: {:ok, task}

  defp maybe_update_parent_task(%Task{parent_task_id: parent_id} = task) do
    parent_task = get_task!(parent_id, task.organization_id)
    new_status = get_parent_task_status(parent_id)

    if parent_task.status != new_status do
      do_update_task(
        parent_task,
        %{"status" => Atom.to_string(new_status)},
        [],
        task.organization_id
      )
    else
      {:ok, parent_task}
    end
  end

  defp maybe_set_completed_at(%{"status" => status} = attrs, %Task{status: old_status}) do
    case status do
      "completed" when old_status != "completed" ->
        Map.put(attrs, "completed_at", NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second))

      status when status in ["open", "progressing"] ->
        Map.put(attrs, "completed_at", nil)

      _ ->
        attrs
    end
  end

  defp maybe_set_completed_at(attrs, _task), do: attrs

  def delete_task(%Task{} = task, org_id) do
    if task.organization_id == org_id do
      result = task |> Repo.delete()
      updated_parent_task = update_parent_task_duration(%{task | id: task.parent_task_id})
      broadcast({:ok, updated_parent_task}, :task_deleted)
      result
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.

  ## Examples

      iex> change_task(task)
      %Ecto.Changeset{data: %Task{}}

  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  @doc """
  Task participations
  """

  def create_task_participation(attrs \\ %{}) do
    %TaskParticipation{}
    |> TaskParticipation.changeset(attrs)
    |> Repo.insert()
  end

  def delete_task_participation(%TaskParticipation{} = task_participation) do
    Repo.delete(task_participation)
  end

  def get_task_participation!(user_id, task_id) do
    Repo.get_by!(TaskParticipation, user_id: user_id, task_id: task_id)
  end

  def list_task_participants(nil), do: []

  def list_task_participants(task_id) do
    Task
    |> Repo.get!(task_id)
    |> Repo.preload(:participants)
    |> Map.get(:participants)
  end

  def list_user_participated_tasks(user_id) do
    User
    |> Repo.get!(user_id)
    |> Repo.preload(:participated_tasks)
    |> Map.get(:participated_tasks)
  end

  def list_tasks_with_participants(org_id) do
    Task
    |> Task.for_org(org_id)
    |> Repo.all()
    |> Repo.preload(:participants)
  end

  def preload_task_participants(task) do
    Repo.preload(task, :participants)
  end

  def update_task_participants(task, participants) do
    task
    |> Task.changeset(%{participants: participants})
    |> Repo.update()
  end

  defp add_participants(task, participants, org_id) do
    Enum.each(participants, fn participant ->
      if participant.organization_id == org_id do
        %TaskParticipation{}
        |> TaskParticipation.changeset(%{task_id: task.id, user_id: participant.id})
        |> Repo.insert()
      end
    end)

    task
  end

  defp update_participants(task, new_participants, org_id) do
    current_participants = list_task_participants(task.id)

    # Remove participants that are not in the new list
    Enum.each(current_participants, fn participant ->
      unless Enum.member?(new_participants, participant) do
        get_task_participation!(participant.id, task.id)
        |> Repo.delete()
      end
    end)

    # Add new participants
    Enum.each(new_participants, fn participant ->
      if participant.organization_id == org_id && !Enum.member?(current_participants, participant) do
        %TaskParticipation{}
        |> TaskParticipation.changeset(%{task_id: task.id, user_id: participant.id})
        |> Repo.insert()
      end
    end)

    task
  end

  def list_task_participants(task_id, org_id) do
    Task
    |> Task.for_org(org_id)
    |> Repo.get!(task_id)
    |> Repo.preload(:participants)
    |> Map.get(:participants)
  end

  def list_user_participated_tasks(user_id, org_id) do
    from(t in Task,
      join: tp in TaskParticipation,
      on: t.id == tp.task_id,
      where: tp.user_id == ^user_id and t.organization_id == ^org_id
    )
    |> Repo.all()
    |> Repo.preload(:participants)
  end

  def subscribe(org_id) do
    Phoenix.PubSub.subscribe(TaskMaster.PubSub, "tasks:#{org_id}")
  end

  defp broadcast({:ok, task}, event) do
    Phoenix.PubSub.broadcast(TaskMaster.PubSub, "tasks:#{task.organization_id}", {event, task})
    {:ok, task}
  end

  defp broadcast({:error, _} = error, _event), do: error
end
