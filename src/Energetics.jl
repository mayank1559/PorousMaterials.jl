using Energetics_Util.jl
const R_OVERLAP_squared = 0.0001 # Units: Angstrom²
#TODO Keep consistant with `check_for_atom_overlap` in src/Crystal.jl? `check_for_atom_overlap` uses the threshold 0.1 Angstrom (0.01 Angstrom²). Which one to use?

"""
	V = lennard_jones(r_squared::Float64, σ_squared::Float64, ϵ::Float64)  (units: Kelvin)

Calculate the lennard jones potential energy given a radius r between two molecules.
σ and ϵ are specific to interaction between two elements.
returns potential energy in units Kelvin.

# Arguments
- `r_squared::Float64`: distance between two (pseudo)atoms in question squared (Angstrom²)
- `σ_squared::Float64`: sigma parameter in Lennard Jones potential squared (units: Angstrom²)
- `ϵ::Float64`: epsilon parameter in Lennard Jones potential (units: Kelvin)
"""
function lennard_jones(r_squared::Float64, σ_squared::Float64, ϵ::Float64)
	ratio = (σ_squared / r_squared) ^ 3
	return 4 * ϵ * (ratio^2 - ratio)
end

"""
    V = vdw_energy(framework::Framework, molecule::Molecule, ljforcefield::LennardJonesForceField, repfactors::Tuple{Int64, Int64, Int64})

Calculates the van der Waals energy for a molecule locates at a specific position in a MOF
supercell. Uses the nearest image convention to find the closest replicate of a specific atom

# Arguments
- `framework::Framework`: Crystal structure
- `molecule::Molecule`: adsorbate (includes position/orientation)
- `ljforcefield::LennardJonesForceField`: Lennard Jones force field
- `repfactors::Tuple{Int64, Int64, Int64}`: replication factors of the home unit cell to build
the supercell, which is the simulation box, such that the nearest image convention can be
applied in this function.
"""
function vdw_energy(framework::Framework, molecule::Molecule,
                    ljforcefield::LennardJonesForceField, repfactors::Tuple{Int64, Int64, Int64})
	energy = 0.0
    # loop over replications of the home unit cell to build the supercell (simulation box)
	for nA = 0:repfactors[1]-1, nB = 0:repfactors[2]-1, nC = 0:repfactors[3]-1
        # loop over atoms of the molecule/adsorbate
        # TODO: think about whether i or k loop should go first for speed. might not matter.
		for i = 1:molecule.n_atoms
			xf_molecule_atom = mod.(framework.box.c_to_f * molecule.x[:, i], repfactors)
            # loop over framework atoms in the home unit cell
			for k = 1:framework.n_atoms
				# Nearest image convention.
                #  If the interaction between the adsorbate molecule and atom k is being looked
                #  at, we'll only look at the interaction between the adsorbate molecule and
                #  the closest replication of atom k. This is done with fractional
                #  coordinates for simplication and transformation to cartesian is done
                #  later.

                # distance in fractional coordinate space
				dxf = xf_molecule_atom - (framework.xf[:, k] + [nA, nB, nC])


				# NIC condensed into a for-loop
				#
				# If the absolute value of the distance between the adsorbate atom and the
				# framework atom is greater than half the replication factor, we know that
				# there is a closer replication of the framework atom.
				#
				# {Replicat.} ||{Supercell}||{Replicat.}
				# |-----|----o||--x--|----o||-----|----o|
				#				  |--dxf--|
				#
				# x = adsorbate atom, o = framework atom
				#
				# dxf is `x_adsorbate - x_framework` so when the adsorbate atom is to the left of
				# the framework atom, dxf is negative.
				# When correcting for the position of the framework atom with the Nearest Image Convention
				# we use `sign(dxf[j]) * repfactors[j]` to change the distance dxf so it gives the distance
				# between the adsorbate atom and the closest replication of the framework atom.
				#
				# In the above example, the framework atom is to the right of the adsorbate atom, and dxf < 0
				# We see that the left replication of `o` is closer to `x`, and we should be calculating the
				# distance between that atom and the adsorbate. So by subtracting `sign(dxf[j]) * repfactors[j]`
				# (remember that `sign(dxf[j]) = -1` in this case) we're adding `repfactors[j]` to the dxf[j] value
				# and dxf[j] becomes positive (which makes sense because we're calculating `x_ads - x_framework`)
				# When checking the other case (where the adsorbate atom is to the right of the framework atom),
				# we see that the same equation holds (because now `sign(dxf[j]) = 1`)

				nearest_image!(dxf, repfactors)

				# Distance in cartesian coordinate space
				dx = framework.box.f_to_c * dxf

				# Lennard Jones parameters (and distance)
				r_squared = dot(dx, dx)

				if r_squared < R_OVERLAP_squared
					# if adsorbate atom overlaps with an atom, return Inf (R_OVERLAP is defined as 0.01 Angstrom, or `R_OVERLAP_squared = 0.0001 Angstrom²)
					return Inf
				else if r_squared < ljforcefield.cutoffradius_squared
                    # add pairwise contribution to potential energy
				    energy += lennard_jones(r_squared,
						ljforcefield.sigmas_squared[framework.atoms[k]][molecule.atoms[i]],
						ljforcefield.epsilons[framework.atoms[k]][molecule.atoms[i]])
				end
			end
		end
	end
	return energy
end # end vdw_energy


"""
	energy = unitcell_energy(frame::Frame, mol::Molecule, ljforcefield::LennardJonesForcefield, repfactors::Tuple(Int64, Int64, Int64); mesh::Array{Int64,1} = [50,50,50])

Calculates the energy in the unitcell with respect to fractional coordinates. Forms an energy matrix with dimensions according to `mesh`.
Can be used in conjucture with `write_to_cube` to make a .cube file for visualization.
"""
function unitcell_energy(frame::Framework, mol::Molecule, ljforcefield::LennardJonesForceField, repfactors::Tuple{Int64, Int64, Int64}; mesh::Array{Int64,1}=[50,50,50])
	range_xf = linspace(0,1,mesh[1])
	range_yf = linspace(0,1,mesh[2])
	range_zf = linspace(0,1,mesh[3])
	energy = zeros(mesh[1],mesh[2],mesh[3])

	for (i,xf) in enumerate(range_xf), (j,yf) in enumerate(range_yf), (k,zf) in enumerate(range_zf)
		mol.x = (frame.box.f_to_c*[xf,yf,zf])[:,:]
		energy[i,j,k] = vdw_energy(frame, mol, ljforcefield, repfactors)
	end
	return energy
end #end unitcell_energy
