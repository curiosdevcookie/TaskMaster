defmodule TaskMasterWeb.TaskLive.TaskIndex do
  use TaskMasterWeb, :live_view

  alias TaskMaster.Tasks
  alias TaskMaster.Tasks.Task
  alias TaskMasterWeb.Helpers.Sorting
  import TaskMasterWeb.Components.TaskComponents
  require Logger

  @impl true
  def mount(params, _session, socket) do
    current_user = socket.assigns.current_user
    sort_by = (params["sort_by"] || "title") |> String.to_existing_atom()
    sort_order = (params["sort_order"] || "asc") |> String.to_existing_atom()

    tasks = Tasks.list_tasks(current_user.organization_id, sort_by, sort_order)
    parent_tasks = Tasks.list_parent_tasks(current_user.organization_id, sort_by, sort_order)
    subtasks = Tasks.list_subtasks(current_user.organization_id, sort_by, sort_order)

    parent_tasks = Enum.map(parent_tasks, &Tasks.preload_task_participants/1)
    subtasks = Enum.map(subtasks, &Tasks.preload_task_participants/1)

    {completed_parent_tasks, open_parent_tasks} =
      Enum.split_with(parent_tasks, &(&1.status == :completed))

    sort_criteria = Sorting.get_default_sort_criteria()

    if connected?(socket) do
      Tasks.subscribe(current_user.organization_id)
    end

    socket
    |> assign(:current_user, current_user)
    |> assign(:page_title, gettext("Listing Tasks"))
    |> assign(:sort_criteria, sort_criteria)
    |> stream(:tasks, tasks)
    |> assign(:open_parent_tasks, open_parent_tasks)
    |> assign(:completed_parent_tasks, completed_parent_tasks)
    |> assign(:subtasks, subtasks)
    |> ok()
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket
    |> maybe_assign_sort_by(request_param(params, "sort_by"))
    |> maybe_assign_sort_order(request_param(params, "sort_order"))
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp request_param(params, key) do
    case Map.get(params, key) do
      "" -> nil
      other -> other
    end
  end

  # Sorting

  defp maybe_assign_sort_by(socket, nil), do: socket

  defp maybe_assign_sort_by(socket, sort_by) do
    socket
    |> assign(:sort_by, Sorting.parse_sort_by(sort_by))
  end

  defp maybe_assign_sort_order(socket, nil), do: socket

  defp maybe_assign_sort_order(socket, sort_order) do
    socket
    |> assign(:sort_order, Sorting.parse_sort_order(sort_order))
  end

  # Apply actions

  defp apply_action(socket, :edit, %{"id" => id}) do
    org_id = socket.assigns.current_user.organization_id
    task = Tasks.get_task!(id, org_id)

    socket
    |> assign(:page_title, gettext("Edit Task"))
    |> assign(:task, task)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New Task"))
    |> assign(:task, %Task{organization_id: socket.assigns.current_user.organization_id})
  end

  defp apply_action(socket, :new_subtask, %{"parent_id" => parent_id}) do
    org_id = socket.assigns.current_user.organization_id
    parent_task = Tasks.get_task!(parent_id, org_id)

    socket
    |> assign(:page_title, gettext("New Subtask"))
    |> assign(:task, %Task{
      parent_task_id: parent_id,
      organization_id: org_id
    })
    |> assign(:parent_task, parent_task)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Listing Tasks"))
    |> assign(:task, nil)
  end

  @impl true
  def handle_info({TaskMasterWeb.TaskLive.TaskComponent, {:saved, task}}, socket) do
    org_id = socket.assigns.current_user.organization_id

    updated_task =
      case task do
        %TaskMaster.Tasks.Task{} -> task
        {:ok, task} -> task
        _ -> Tasks.get_task!(task.id, org_id)
      end
      |> Tasks.preload_task_participants()

    {:noreply,
     socket
     |> stream_insert(:tasks, updated_task)
     |> push_patch(to: ~p"/#{socket.assigns.current_user.id}/tasks")}
  end

  @impl true
  def handle_info({:task_created, new_task}, socket) do
    {:noreply, update_task_in_assigns(socket, new_task)}
  end

  @impl true
  def handle_info({:task_updated, updated_task}, socket) do
    org_id = socket.assigns.current_user.organization_id

    # Refresh the updated task
    refreshed_task = Tasks.get_task!(updated_task.id, org_id) |> Tasks.preload_task_participants()

    # If it's a subtask, also refresh its parent
    parent_task =
      if refreshed_task.parent_task_id do
        Tasks.get_task!(refreshed_task.parent_task_id, org_id)
        |> Tasks.preload_task_participants()
      end

    socket = update_task_in_assigns(socket, refreshed_task)

    socket =
      if parent_task do
        update_task_in_assigns(socket, parent_task)
      else
        socket
      end

    {:noreply, socket}
  end

  defp update_task_in_assigns(socket, updated_task) do
    socket
    |> stream_insert(:tasks, updated_task)
    |> update_parent_tasks(updated_task)
    |> update_subtasks(updated_task)
  end

  defp update_parent_tasks(socket, %Task{} = updated_task) do
    if is_nil(updated_task.parent_task_id) do
      {open_parent_tasks, completed_parent_tasks} =
        (socket.assigns.open_parent_tasks ++ socket.assigns.completed_parent_tasks)
        |> Enum.map(fn task ->
          if task.id == updated_task.id, do: updated_task, else: task
        end)
        |> Enum.split_with(&(&1.status != :completed))

      socket
      |> assign(:open_parent_tasks, open_parent_tasks)
      |> assign(:completed_parent_tasks, completed_parent_tasks)
    else
      socket
    end
  end

  defp update_subtasks(socket, %Task{} = updated_task) do
    socket
    |> update(:subtasks, fn tasks ->
      Enum.map(tasks, fn task ->
        if task.id == updated_task.id, do: updated_task, else: task
      end)
    end)
  end

  @impl true
  def handle_event("add_subtask", %{"parent_id" => parent_id}, socket) do
    org_id = socket.assigns.current_user.organization_id
    parent_id |> dbg()
    parent_task = Tasks.get_task!(parent_id, org_id)

    {:noreply,
     socket
     |> assign(:parent_task, parent_task)
     |> assign(:page_title, gettext("New Subtask"))
     |> push_patch(to: ~p"/#{socket.assigns.current_user.id}/tasks/#{parent_task.id}/new_subtask")}
  end

  @impl true
  def handle_event(
        "toggle_task_status",
        %{"id" => id, "current_status" => current_status},
        socket
      ) do
    org_id = socket.assigns.current_user.organization_id
    task = Tasks.get_task!(id, org_id)

    new_status =
      case current_status do
        "completed" -> :open
        _ -> :completed
      end

    Logger.info(
      "Toggling task status. Task ID: #{id}, Current status: #{current_status}, New status: #{new_status}"
    )

    case Tasks.update_task(task, %{status: new_status}, task.participants, org_id) do
      %Task{} = updated_task ->
        Logger.info("Task updated successfully. New status: #{updated_task.status}")
        {:noreply, update_task_in_assigns(socket, updated_task)}

      {:error, :subtasks_not_completed} ->
        Logger.warning("Cannot complete task: not all subtasks are completed")

        {:noreply,
         put_flash(socket, :error, "Cannot complete task: not all subtasks are completed")}

      {:error, changeset} ->
        Logger.error("Failed to update task status: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Failed to update task status")}
    end
  end

  @impl true
  def handle_event("sort_tasks", %{"field" => field, "status" => old_status}, socket) do
    {new_criteria, sort_by, sort_order} = Sorting.compute_new_sort_criteria(field, old_status)
    current_user = socket.assigns.current_user

    tasks = Tasks.list_tasks(current_user.organization_id, sort_by, sort_order)
    parent_tasks = Tasks.list_parent_tasks(current_user.organization_id, sort_by, sort_order)
    subtasks = Tasks.list_subtasks(current_user.organization_id, sort_by, sort_order)

    {completed_parent_tasks, open_parent_tasks} =
      Enum.split_with(parent_tasks, &(&1.status == :completed))

    socket
    |> assign(:sort_by, sort_by)
    |> assign(:sort_order, sort_order)
    |> assign(:sort_criteria, new_criteria)
    |> assign(:tasks, tasks)
    |> assign(:open_parent_tasks, open_parent_tasks)
    |> assign(:completed_parent_tasks, completed_parent_tasks)
    |> assign(:subtasks, subtasks)
    |> push_patch(
      to: ~p"/#{socket.assigns.current_user.id}/tasks?sort_by=#{sort_by}&sort_order=#{sort_order}"
    )
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="flex gap-1 my-4">
      <.sort_button_list sort_criteria={@sort_criteria} />
    </section>
    <div class="flex flex-col gap-1 h-[calc(100vh-6rem)]">
      <div class="h-[80%] overflow-hidden pb-20">
        <.header class="mb-2">
          <p>
            <%= gettext("Open Tasks") %>
          </p>

          <:actions>
            <.link patch={~p"/#{@current_user.id}/tasks/new"}>
              <.button class="btn-primary"><%= gettext("New Task") %></.button>
            </.link>
          </:actions>
        </.header>

        <div class="h-full overflow-y-auto">
          <.task_list
            parent_tasks={@open_parent_tasks}
            subtasks={@subtasks}
            current_user={@current_user}
            navigate_fn={fn parent_task -> ~p"/#{@current_user.id}/tasks/#{parent_task}" end}
            patch_fn={
              fn parent_task -> ~p"/#{@current_user.id}/tasks/#{parent_task.id}/new_subtask" end
            }
          />
        </div>
      </div>
      <div class="h-[30%] overflow-hidden pb-20">
        <.footer class="mb-4">
          <p><%= gettext("Completed Tasks") %></p>
        </.footer>

        <div class="h-full overflow-y-auto">
          <.task_list
            parent_tasks={@completed_parent_tasks}
            subtasks={@subtasks}
            current_user={@current_user}
            navigate_fn={fn parent_task -> ~p"/#{@current_user.id}/tasks/#{parent_task}" end}
            patch_fn={
              fn parent_task -> ~p"/#{@current_user.id}/tasks/#{parent_task.id}/new_subtask" end
            }
          />
        </div>
      </div>
    </div>

    <.modal
      :if={@live_action in [:new, :edit, :new_subtask]}
      id="task-modal"
      show
      on_cancel={JS.patch(~p"/#{@current_user.id}/tasks")}
    >
      <.live_component
        module={TaskMasterWeb.TaskLive.TaskComponent}
        id={@task.id || :new}
        title={@page_title}
        action={@live_action}
        task={@task}
        parent_id={{@task.parent_task_id, @task.id}}
        current_user={@current_user}
        patch={~p"/#{@current_user.id}/tasks"}
      />
    </.modal>
    """
  end
end
