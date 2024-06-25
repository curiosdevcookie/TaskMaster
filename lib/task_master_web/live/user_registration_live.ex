defmodule TaskMasterWeb.UserRegistrationLive do
  use TaskMasterWeb, :live_view

  alias TaskMaster.Accounts
  alias TaskMaster.Accounts.User
  alias Ecto.Changeset

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Register for an account
        <:subtitle>
          Already registered?
          <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
            Log in
          </.link>
          to your account now.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log_in?_action=registered"}
        method="post"
      >
        <.error :if={@check_errors}>
          Oops, something went wrong! Please check the errors below.
        </.error>
        <.input field={@form[:first_name]} type="text" label="First name" required />
        <.input field={@form[:last_name]} type="text" label="Last name" required />
        <.input field={@form[:nick_name]} type="text" label="Nick name" />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input
          field={@form[:password]}
          type="password"
          placeholder="Enter password"
          required
          autocomplete="new-password"
          phx-input="check_password"
          is_new_password={true}
          password_strength={@password_strength}
        />

        <.input
          field={@form[:password_confirmation]}
          type="password"
          placeholder="Repeat password"
          required
          autocomplete="new-password"
          phx-input="check_password"
        />

        <:actions>
          <.button
            phx-disable-with="Creating account..."
            class="w-full"
            disabled={Enum.empty?(@form.errors)}
          >
            Create an account
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign(:password_strength, 0)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    dbg(user_params)

    password_strength = Ecto.Changeset.get_field(changeset, :password_strength, 0)

    socket =
      socket
      |> assign(:password_strength, password_strength)
      |> assign_form(Map.put(changeset, :action, :validate))

    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user") |> dbg()

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
