defmodule TaskMaster.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :first_name, :citext
      add :last_name, :citext
      add :company, :citext, null: false
      add :area_of_expertise, :citext, null: false
      add :email, :citext
      add :phone, :string
      add :mobile, :string
      add :street, :string
      add :street_number, :string
      add :postal_code, :string
      add :city, :string
      add :notes, :text

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end
  end
end
