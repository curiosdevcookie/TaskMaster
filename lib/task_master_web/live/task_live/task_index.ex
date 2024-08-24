defmodule TaskMasterWeb.TaskLive.TaskIndex do
  use TaskMasterWeb, :live_view

  alias TaskMaster.Tasks
  alias TaskMaster.Tasks.Task
  import TaskMasterWeb.Components.TaskComponents

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    tasks = Tasks.list_tasks_with_participants(current_user.organization_id)
    parent_tasks = Tasks.list_parent_tasks(current_user.organization_id)
    subtasks = Tasks.list_subtasks(current_user.organization_id)

    if connected?(socket) do
      Tasks.subscribe(current_user.organization_id)
    end

    socket
    |> assign(:current_user, current_user)
    |> assign(:page_title, gettext("Listing Tasks"))
    |> stream(:tasks, tasks)
    |> assign(:parent_tasks, parent_tasks)
    |> assign(:subtasks, subtasks)
    |> ok()
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

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
    updated_task = Tasks.get_task!(task.id, org_id) |> Tasks.preload_task_participants()

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
    {:noreply, update_task_in_assigns(socket, updated_task)}
  end

   defp update_task_in_assigns(socket, updated_task) do
    socket
    |> stream_insert(:tasks, updated_task)
    |> update(:parent_tasks, fn tasks ->
      if is_nil(updated_task.parent_task_id) do
        Enum.map(tasks, fn task ->
          if task.id == updated_task.id, do: updated_task, else: task
        end)
      else
        tasks
      end
    end)
    |> update(:subtasks, fn tasks ->
      if not is_nil(updated_task.parent_task_id) do
        Enum.map(tasks, fn task ->
          if task.id == updated_task.id, do: updated_task, else: task
        end)
      else
        tasks
      end
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
  def handle_event("toggle_task_status", %{"id" => id, "current_status" => current_status}, socket) do
    org_id = socket.assigns.current_user.organization_id
    task = Tasks.get_task!(id, org_id)

    new_status = if current_status == "completed", do: "open", else: "completed" |> dbg()

    case Tasks.update_task(task, %{status: new_status}, task.participants, org_id) do
      {:ok, _updated_task} ->
        {:noreply, socket}

      {:error, :subtasks_not_completed} ->
        {:noreply, put_flash(socket, :error, "Cannot complete task: not all subtasks are completed")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task status")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      <%= gettext("Open Tasks") %>
      <:actions>
        <.link patch={~p"/#{@current_user.id}/tasks/new"}>
          <.button class="btn-primary"><%= gettext("New Task") %></.button>
        </.link>
      </:actions>
    </.header>

    <.task_list
      parent_tasks={@parent_tasks}
      subtasks={@subtasks}
      current_user={@current_user}
      navigate_fn={fn parent_task -> ~p"/#{@current_user.id}/tasks/#{parent_task}" end}
      patch_fn={fn parent_task -> ~p"/#{@current_user.id}/tasks/#{parent_task.id}/new_subtask" end}

    />

    <h2><%= gettext("Done Tasks") %></h2>

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
